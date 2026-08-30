from __future__ import annotations

import json
import threading
from copy import deepcopy
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from sre_control_plane.contracts import REQUIRED_CAPABILITIES, InvestigationRequest, ResultStatus
from sre_control_plane.executor import CapabilityReport, ExecutorStatus, StartInvestigationCommand
from sre_control_plane.fake_executor import CANONICAL_FAKE_RESULT
from sre_control_plane.holmesgpt_executor import (
    HOLMESGPT_EXECUTOR_ID,
    MAX_HOLMESGPT_RESPONSE_BYTES,
    HolmesGptHttpConfig,
    HolmesGptHttpExecutor,
    HolmesGptHttpResponse,
    HolmesGptExecutorError,
    HolmesGptRejected,
    HolmesGptUnavailable,
    UrllibHolmesGptTransport,
)
from sre_control_plane.states import AttemptState, TaskState
from sre_control_plane.workflow import SreInvestigationWorkflow
from sre_control_plane.persistence import Base


ROOT = Path(__file__).resolve().parents[2]


def response(
    status: int,
    payload: object,
    headers: dict[str, str] | None = None,
) -> HolmesGptHttpResponse:
    return HolmesGptHttpResponse(
        status=status,
        headers=headers if headers is not None else {"Content-Type": "application/json"},
        body=json.dumps(payload).encode("utf-8"),
    )


@pytest.fixture()
def session_factory(tmp_path: Path):
    engine = create_engine(f"sqlite:///{tmp_path / 'holmesgpt.db'}")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, expire_on_commit=False)


def local_capabilities(**changes) -> CapabilityReport:
    payload = {
        "executor_id": HOLMESGPT_EXECUTOR_ID,
        "schema_versions": ["1.0"],
        "declared_capabilities": sorted(REQUIRED_CAPABILITIES),
        "denied_capabilities": [
            "kubernetes.write", "rollout.mutate", "gitops.write", "deployment.write",
            "remediation.execute", "pull_request.merge", "incident.close", "secrets.read",
        ],
        "target_scope": {
            "namespace": "online-shop-stage", "workload": "frontend",
            "rollout": "frontend", "gitops_application": "online-shop-stage",
        },
        "auth_mode": "local-fixture-no-credentials",
        "verification_evidence": ["deterministic local fixture; live runtime NOT TESTED"],
        "supports_idempotent_start": True,
        "supports_status_lookup": False,
        "idempotency_scope": "process_local",
    }
    payload.update(changes)
    return CapabilityReport.model_validate(payload)


def command() -> StartInvestigationCommand:
    request = request_example("holmesgpt-http-request")
    return StartInvestigationCommand(
        request=request, task_id="task-holmesgpt", attempt_id="task-holmesgpt-a1",
        idempotency_key="task-holmesgpt-a1", fencing_token=1,
    )


def request_example(request_id: str) -> InvestigationRequest:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    payload["request_id"] = request_id
    payload["signal"]["fingerprint"] = request_id
    return InvestigationRequest.model_validate(payload)


def result_payload(command: StartInvestigationCommand, status: ResultStatus = ResultStatus.SUCCEEDED) -> dict:
    payload = deepcopy(CANONICAL_FAKE_RESULT)
    payload.update(
        result_id=f"result-{command.attempt_id}",
        task_id=command.task_id,
        attempt_id=command.attempt_id,
        executor_id=HOLMESGPT_EXECUTOR_ID,
        status=status,
    )
    for evidence, reference in zip(payload["evidence"], [
        "sre-platform://approved/slo:error_ratio_5m",
        "sre-platform://approved/slo:burn_rate_5m",
        "sre-platform://approved/ingress:online-shop-frontend",
        "sre-platform://approved/ingress:online-shop-frontend",
    ], strict=True):
        evidence["reference"] = reference
    return payload


def executor(responses: list[HolmesGptHttpResponse], capabilities: CapabilityReport | None = None) -> tuple[HolmesGptHttpExecutor, QueueTransport]:
    transport = QueueTransport(responses)
    return (
        HolmesGptHttpExecutor(
            HolmesGptHttpConfig(
                endpoint="http://127.0.0.1:18080", local_test_mode=True,
                capability_report=capabilities or local_capabilities(),
            ),
            transport,
        ),
        transport,
    )


def test_local_http_fixture_maps_schema_valid_partial_result_and_reuses_identity() -> None:
    invocation = command()
    adapter, transport = executor([response(200, {"analysis": result_payload(invocation, ResultStatus.PARTIAL)})])

    assert adapter.describe_capabilities().executor_id == HOLMESGPT_EXECUTOR_ID
    first = adapter.start_investigation(invocation)
    repeated = adapter.start_investigation(invocation)

    assert first.status == ExecutorStatus.SUCCEEDED
    assert repeated == first
    assert len(transport.calls) == 1
    payload = json.loads(transport.calls[0][3])
    assert transport.calls[0][:2] == ("POST", "/api/chat")
    assert payload["stream"] is False and payload["enable_tool_approval"] is False
    assert json.loads(payload["ask"])["fencing_token"] == 1
    assert adapter.get_result(invocation.attempt_id, invocation.idempotency_key).status == ResultStatus.PARTIAL


def test_concurrent_same_key_calls_share_one_http_post() -> None:
    invocation = command()
    transport = BlockingTransport(response(200, {"analysis": result_payload(invocation)}))
    adapter = HolmesGptHttpExecutor(
        HolmesGptHttpConfig(
            endpoint="http://127.0.0.1:18080", local_test_mode=True,
            capability_report=local_capabilities(),
        ),
        transport,
    )

    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(adapter.start_investigation, invocation)
        assert transport.started.wait(timeout=5)
        second = pool.submit(adapter.start_investigation, invocation)
        with pytest.raises(TimeoutError):
            second.result(timeout=0.1)
        transport.release.set()
        assert first.result(timeout=5) == second.result(timeout=5)

    assert transport.calls == 1


def test_same_key_with_different_canonical_request_is_rejected() -> None:
    invocation = command()
    adapter, transport = executor([response(200, {"analysis": result_payload(invocation)})])
    adapter.start_investigation(invocation)
    changed_request = invocation.request.model_copy(
        update={"signal": invocation.request.signal.model_copy(update={"fingerprint": "different-fingerprint"})}
    )
    conflicting = invocation.model_copy(update={"request": changed_request})

    with pytest.raises(HolmesGptRejected, match="idempotency identity conflicts"):
        adapter.start_investigation(conflicting)

    assert len(transport.calls) == 1


def test_new_executor_instance_marks_process_local_state_stale() -> None:
    invocation = command()
    first, _ = executor([response(200, {"analysis": result_payload(invocation)})])
    first.start_investigation(invocation)
    restarted, _ = executor([])

    assert restarted.describe_capabilities().supports_status_lookup is False
    assert restarted.describe_capabilities().idempotency_scope == "process_local"
    assert restarted.get_status(invocation.attempt_id, invocation.idempotency_key).status == ExecutorStatus.STALE
    with pytest.raises(HolmesGptRejected):
        restarted.get_result(invocation.attempt_id, invocation.idempotency_key)


def test_nonfixture_capability_declaration_fails_closed() -> None:
    adapter = HolmesGptHttpExecutor(
        HolmesGptHttpConfig(
            endpoint="https://holmes.internal",
            capability_report=local_capabilities(
                auth_mode="private-network-not-tested",
                supports_status_lookup=True,
                idempotency_scope="durable",
            ),
        ),
        QueueTransport([]),
    )

    with pytest.raises(HolmesGptRejected, match="not fail-closed"):
        adapter.describe_capabilities()


@pytest.mark.parametrize("response_value", [
    response(301, {}),
    response(200, {"analysis": {"unexpected": "shape"}}),
    HolmesGptHttpResponse(200, {}, b"{"),
    HolmesGptHttpResponse(200, {}, b"x" * (MAX_HOLMESGPT_RESPONSE_BYTES + 1)),
])
def test_redirected_malformed_and_oversized_responses_fail_closed(response_value: HolmesGptHttpResponse) -> None:
    adapter, _ = executor([response_value])
    with pytest.raises(HolmesGptRejected):
        adapter.start_investigation(command())


def test_unavailable_response_is_controlled_without_exposing_body() -> None:
    adapter, _ = executor([response(503, {"error": {"detail": "token=not-disclosed"}})])
    with pytest.raises(HolmesGptUnavailable) as exc_info:
        adapter.start_investigation(command())
    assert "token" not in str(exc_info.value)


@pytest.mark.parametrize("headers", [
    {},
    {"Content-Type": "text/plain"},
    {"Content-Type": "application json"},
    {"Content-Type": "application/json, text/plain"},
])
def test_successful_response_requires_json_compatible_content_type(headers: dict[str, str]) -> None:
    invocation = command()
    adapter, _ = executor([response(200, {"analysis": result_payload(invocation)}, headers)])

    with pytest.raises(HolmesGptRejected):
        adapter.start_investigation(invocation)


def test_successful_response_accepts_json_compatible_content_type() -> None:
    invocation = command()
    adapter, _ = executor([
        response(
            200,
            {"analysis": result_payload(invocation)},
            {"Content-Type": "application/vnd.holmes+json; charset=utf-8"},
        )
    ])

    assert adapter.start_investigation(invocation).status == ExecutorStatus.SUCCEEDED


@pytest.mark.parametrize("redirect_status", [301, 302, 307, 308])
def test_urllib_transport_does_not_follow_local_redirects(redirect_status: int) -> None:
    target_calls: list[str] = []

    class RedirectFixture(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802: stdlib handler API
            if self.path == "/api/chat":
                self.send_response(redirect_status)
                self.send_header("Location", "/redirect-target")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            target_calls.append(self.headers.get("Authorization", ""))
            self.send_response(204)
            self.end_headers()

        def log_message(self, _format: str, *_args: object) -> None:
            return

    server = ThreadingHTTPServer(("127.0.0.1", 0), RedirectFixture)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        transport = UrllibHolmesGptTransport(f"http://127.0.0.1:{server.server_port}", 5)
        result = transport.request("POST", "/api/chat", {"Authorization": "not-a-secret"}, b"{}")
    finally:
        server.shutdown()
        thread.join()
        server.server_close()

    assert result.status == redirect_status
    assert target_calls == []


def test_unsafe_evidence_and_missing_mutation_denial_fail_closed() -> None:
    invocation = command()
    unsafe = result_payload(invocation)
    unsafe["evidence"][0]["reference"] = "https://unapproved.example/evidence"
    adapter, _ = executor([response(200, {"analysis": unsafe})])
    with pytest.raises(HolmesGptRejected):
        adapter.start_investigation(invocation)

    missing_denial = local_capabilities(denied_capabilities=["kubernetes.write"])
    adapter, _ = executor([], missing_denial)
    with pytest.raises(HolmesGptRejected):
        adapter.describe_capabilities()


def test_controlled_errors_do_not_chain_or_expose_adapter_secrets(caplog, session_factory) -> None:
    secret = "recognizable-adapter-secret"
    malformed_report = CapabilityReport.model_construct(executor_id=secret)
    malformed_adapter, _ = executor([], malformed_report)
    assert_secret_safe_error(secret, caplog, lambda: malformed_adapter.describe_capabilities())

    invocation = command()
    malformed_analysis, _ = executor([
        response(200, {"analysis": {"untrusted": secret}})
    ])
    assert_secret_safe_error(secret, caplog, lambda: malformed_analysis.start_investigation(invocation))

    transport_error_adapter = HolmesGptHttpExecutor(
        HolmesGptHttpConfig(
            endpoint="http://127.0.0.1:18080",
            local_test_mode=True,
            capability_report=local_capabilities(),
        ),
        SecretTransport(secret),
    )
    assert_secret_safe_error(secret, caplog, lambda: transport_error_adapter.start_investigation(invocation))

    workflow = SreInvestigationWorkflow(session_factory, transport_error_adapter)
    task = workflow.submit_request(invocation.request)
    view = workflow.run_dispatch_tick("secret-safe-dispatch")
    durable_view = workflow.get_task(task.task_id)

    assert view.reason == "attempt_executed"
    assert durable_view.task_state == TaskState.READY
    assert durable_view.attempt is not None and durable_view.attempt.state == AttemptState.DISPATCH_FAILED
    assert secret not in json.dumps(durable_view.model_dump(mode="json"))
    assert secret not in caplog.text


def test_secret_bearing_adapter_failures_never_enter_durable_state(caplog, session_factory) -> None:
    secret = "durable-adapter-secret"
    adapters = [
        HolmesGptHttpExecutor(
            HolmesGptHttpConfig(
                endpoint="http://127.0.0.1:18080",
                local_test_mode=True,
                capability_report=CapabilityReport.model_construct(executor_id=secret),
            ),
            QueueTransport([]),
        ),
        executor([response(200, {"analysis": {"untrusted": secret}})])[0],
        HolmesGptHttpExecutor(
            HolmesGptHttpConfig(
                endpoint="http://127.0.0.1:18080",
                local_test_mode=True,
                capability_report=local_capabilities(),
            ),
            SecretTransport(secret),
        ),
    ]

    for index, adapter in enumerate(adapters):
        workflow = SreInvestigationWorkflow(session_factory, adapter)
        task = workflow.submit_request(request_example(f"durable-secret-{index}"))
        workflow.run_dispatch_tick(f"durable-secret-{index}")
        durable_view = workflow.get_task(task.task_id)

        assert secret not in json.dumps(durable_view.model_dump(mode="json"))
        assert durable_view.task_state == TaskState.READY

    assert secret not in caplog.text


def test_cancellation_is_unsupported_and_preserves_terminal_result() -> None:
    invocation = command()
    adapter, _ = executor([response(200, {"analysis": result_payload(invocation)})])
    adapter.start_investigation(invocation)

    with pytest.raises(HolmesGptRejected, match="cancellation is unsupported") as exc_info:
        adapter.cancel_attempt(invocation.attempt_id, invocation.idempotency_key)

    assert exc_info.value.__cause__ is None
    assert exc_info.value.__context__ is None
    assert adapter.get_status(invocation.attempt_id, invocation.idempotency_key).status == ExecutorStatus.SUCCEEDED
    assert adapter.get_result(invocation.attempt_id, invocation.idempotency_key).status == ResultStatus.SUCCEEDED


def test_cancellation_during_inflight_request_is_unsupported_and_late_success_is_retained() -> None:
    invocation = command()
    transport = BlockingTransport(response(200, {"analysis": result_payload(invocation)}))
    adapter = HolmesGptHttpExecutor(
        HolmesGptHttpConfig(
            endpoint="http://127.0.0.1:18080",
            local_test_mode=True,
            capability_report=local_capabilities(),
        ),
        transport,
    )

    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(adapter.start_investigation, invocation)
        assert transport.started.wait(timeout=5)
        with pytest.raises(HolmesGptRejected, match="cancellation is unsupported"):
            adapter.cancel_attempt(invocation.attempt_id, invocation.idempotency_key)
        transport.release.set()
        assert future.result(timeout=5).status == ExecutorStatus.SUCCEEDED

    assert adapter.get_status(invocation.attempt_id, invocation.idempotency_key).status == ExecutorStatus.SUCCEEDED


def test_endpoint_userinfo_and_raw_configuration_secret_never_escape(monkeypatch, caplog) -> None:
    secret = "recognizable-holmes-secret"
    with pytest.raises(ValueError) as endpoint_error:
        HolmesGptHttpConfig(endpoint=f"http://{secret}@127.0.0.1:18080", local_test_mode=True)
    assert secret not in str(endpoint_error.value)
    assert secret not in repr(endpoint_error.value)
    assert endpoint_error.value.__cause__ is None
    assert endpoint_error.value.__context__ is None

    monkeypatch.setenv("SRE_CONTROL_PLANE_HOLMESGPT_ENDPOINT", "http://127.0.0.1:18080")
    monkeypatch.setenv("SRE_CONTROL_PLANE_HOLMESGPT_LOCAL_TEST_MODE", "1")
    monkeypatch.setenv("SRE_CONTROL_PLANE_HOLMESGPT_CAPABILITIES_JSON", json.dumps({"executor_id": secret}))
    from sre_control_plane.config import load_settings

    with pytest.raises(ValueError) as config_error:
        load_settings()
    assert secret not in str(config_error.value)
    assert secret not in repr(config_error.value)
    assert config_error.value.__cause__ is None
    assert config_error.value.__context__ is None
    assert secret not in caplog.text


def test_schema_valid_failed_result_preserves_audit_and_returns_task_to_ready(session_factory) -> None:
    request = request_example("holmesgpt-failed-result")
    predicted_task_id = "task-" + __import__("hashlib").sha256(request.request_id.encode()).hexdigest()[:16]
    invocation = StartInvestigationCommand(
        request=request, task_id=predicted_task_id, attempt_id=f"{predicted_task_id}-a1",
        idempotency_key=f"{predicted_task_id}-a1", fencing_token=1,
    )
    adapter, _ = executor([response(200, {"analysis": result_payload(invocation, ResultStatus.FAILED)})])
    workflow = SreInvestigationWorkflow(session_factory, adapter)
    task = workflow.submit_request(request)

    workflow.run_dispatch_tick("holmesgpt-failed-result")
    view = workflow.get_task(task.task_id)

    assert view.task_state == TaskState.READY
    assert view.attempt is not None and view.attempt.state == AttemptState.FAILED
    assert view.results[0].status == ResultStatus.FAILED


class QueueTransport:
    def __init__(self, responses: list[HolmesGptHttpResponse]) -> None:
        self.responses = responses
        self.calls: list[tuple[str, str, dict[str, str], bytes | None]] = []

    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> HolmesGptHttpResponse:
        self.calls.append((method, path, headers, body))
        return self.responses.pop(0)


class BlockingTransport:
    def __init__(self, response_value: HolmesGptHttpResponse) -> None:
        self._response = response_value
        self.calls = 0
        self.started = threading.Event()
        self.release = threading.Event()

    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> HolmesGptHttpResponse:
        self.calls += 1
        self.started.set()
        if not self.release.wait(timeout=5):
            raise TimeoutError("test transport did not release")
        return self._response


class SecretTransport:
    def __init__(self, secret: str) -> None:
        self._secret = secret

    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> HolmesGptHttpResponse:
        raise RuntimeError(f"remote failure: {self._secret}")


def assert_secret_safe_error(secret: str, caplog, operation) -> None:
    with pytest.raises(HolmesGptExecutorError) as exc_info:
        operation()
    error = exc_info.value
    assert secret not in str(error)
    assert secret not in repr(error)
    assert error.__cause__ is None
    assert error.__context__ is None
    assert secret not in caplog.text
