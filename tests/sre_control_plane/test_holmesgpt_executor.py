from __future__ import annotations

import json
import threading
from copy import deepcopy
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
    HolmesGptRejected,
    HolmesGptUnavailable,
    UrllibHolmesGptTransport,
)
from sre_control_plane.states import AttemptState, TaskState
from sre_control_plane.workflow import SreInvestigationWorkflow
from sre_control_plane.persistence import Base


ROOT = Path(__file__).resolve().parents[2]


def response(status: int, payload: object) -> HolmesGptHttpResponse:
    return HolmesGptHttpResponse(status=status, headers={}, body=json.dumps(payload).encode("utf-8"))


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
        "supports_status_lookup": True,
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
