from __future__ import annotations

import json
from pathlib import Path

import pytest

from sre_control_plane.contracts import REQUIRED_CAPABILITIES, InvestigationRequest, ResultStatus
from sre_control_plane.executor import ExecutorStatus, StartInvestigationCommand
from sre_control_plane.sre_replay_executor import (
    SRE_REPLAY_EXECUTOR_ID,
    SRE_REPLAY_SCENARIO_ID,
    SreReplayExecutor,
    SreReplayExecutorConfig,
    SreReplayProviderDeclarations,
    approved_replay_provider_declarations,
    approved_replay_provider_declarations_json,
    parse_replay_provider_declarations,
)

ROOT = Path(__file__).resolve().parents[2]


def request_example(request_id: str = "sre-replay-request") -> InvestigationRequest:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    payload["request_id"] = request_id
    payload["signal"]["fingerprint"] = request_id
    return InvestigationRequest.model_validate(payload)


def command(request_id: str = "sre-replay-request") -> StartInvestigationCommand:
    request = request_example(request_id)
    return StartInvestigationCommand(
        request=request,
        task_id="task-sre-replay",
        attempt_id="attempt-sre-replay-a1",
        idempotency_key="attempt-sre-replay-a1",
        fencing_token=1,
    )


def executor(declarations: SreReplayProviderDeclarations | None = None) -> SreReplayExecutor:
    return SreReplayExecutor(
        SreReplayExecutorConfig(
            scenario_id=SRE_REPLAY_SCENARIO_ID,
            provider_declarations=declarations or approved_replay_provider_declarations(),
        )
    )


def declaration_payload() -> dict:
    return json.loads(approved_replay_provider_declarations_json())


def test_sre_replay_capabilities_are_bounded_and_read_only() -> None:
    report = executor().describe_capabilities()

    assert report.executor_id == SRE_REPLAY_EXECUTOR_ID
    assert set(report.declared_capabilities) == REQUIRED_CAPABILITIES
    assert report.target_scope == {
        "namespace": "online-shop-stage",
        "workload": "frontend",
        "rollout": "frontend",
        "gitops_application": "online-shop-stage",
    }
    assert "kubernetes.write" in report.denied_capabilities
    assert "gitops.write" in report.denied_capabilities
    assert report.auth_mode == "sanitized-replay-fixture-no-credentials"
    assert any("no live staging or production validation" in item for item in report.verification_evidence)


@pytest.mark.parametrize(
    "mutator",
    [
        lambda payload: payload["kubernetes"].update({"namespaces": ["online-shop-prod"]}),
        lambda payload: payload["kubernetes"].update({"verbs": ["get", "list", "patch"]}),
        lambda payload: payload["kubernetes"].update({"resources": ["*"]}),
        lambda payload: payload["prometheus"].update({"query_allowlist": ["up"]}),
        lambda payload: payload["prometheus"].update({"query_names": ["slo:error_ratio_5m"]}),
        lambda payload: payload["gitops"].update({"repository": "Other/sre-platform"}),
        lambda payload: payload["gitops"].update({"actions": ["read_file", "write_file"]}),
        lambda payload: payload["gitops"].update({"paths": ["*"]}),
        lambda payload: payload["recovery_observation"].update({"actions": ["observe_status", "restart"]}),
        lambda payload: payload["recovery_observation"].update({"claims_live_recovery": True}),
    ],
)
def test_sre_replay_declaration_fails_closed_for_unsafe_scope(mutator) -> None:
    payload = declaration_payload()
    mutator(payload)

    with pytest.raises(ValueError):
        SreReplayProviderDeclarations.model_validate(payload)


def test_sre_replay_declaration_rejects_malformed_and_unsafe_values_without_details() -> None:
    unsafe = "token=recognizable-secret-value"
    payload = declaration_payload()
    payload["gitops"]["paths"].append(unsafe)

    with pytest.raises(ValueError) as exc_info:
        parse_replay_provider_declarations(json.dumps(payload))

    assert unsafe not in str(exc_info.value)
    assert unsafe not in repr(exc_info.value)
    assert exc_info.value.__cause__ is None
    assert exc_info.value.__context__ is None


def test_sre_replay_start_is_semantically_idempotent() -> None:
    replay = executor()
    start = replay.start_investigation(command())

    repeated = replay.start_investigation(command())

    assert start == repeated
    assert start.status is ExecutorStatus.SUCCEEDED


def test_sre_replay_rejects_idempotency_conflict() -> None:
    replay = executor()
    replay.start_investigation(command("sre-replay-request-one"))
    conflicting = command("sre-replay-request-two")

    with pytest.raises(RuntimeError, match="conflicts"):
        replay.start_investigation(conflicting)


def test_sre_replay_returns_deterministic_schema_valid_fixture_result() -> None:
    replay = executor()
    replay.start_investigation(command())

    first = replay.get_result("attempt-sre-replay-a1", "attempt-sre-replay-a1")
    second = replay.get_result("attempt-sre-replay-a1", "attempt-sre-replay-a1")

    assert first == second
    assert first.status is ResultStatus.SUCCEEDED
    assert first.executor_id == SRE_REPLAY_EXECUTOR_ID
    assert first.recovery_status == "not_checked"
    assert all(item.reference.startswith("sre-platform://replay/approved-stage-frontend-slo-v1/") for item in first.evidence)
    assert any("Replay/fixture validation only" in item for item in first.limitations)
    assert any("Approved read-only scope" in item for item in first.limitations)
    assert all(not recommendation.executes_remediation for recommendation in first.recommendations)


def test_sre_replay_rejects_requests_outside_approved_scope() -> None:
    bad_request = request_example()
    payload = bad_request.model_dump(mode="json")
    payload["scope"]["cluster"] = "prod"
    bad_command = command()
    bad_command = bad_command.model_copy(update={"request": InvestigationRequest.model_validate({**payload, "scope": {**payload["scope"], "cluster": "prod"}})})

    with pytest.raises(RuntimeError, match="approved scope"):
        executor().start_investigation(bad_command)


def test_sre_replay_stale_status_for_unknown_attempt() -> None:
    status = executor().get_status("unknown", "unknown")

    assert status.status is ExecutorStatus.STALE


def test_sre_replay_fixture_contains_no_raw_secrets_or_private_endpoints() -> None:
    replay = executor()
    replay.start_investigation(command())
    payload = replay.get_result("attempt-sre-replay-a1", "attempt-sre-replay-a1").model_dump(mode="json")
    serialized = json.dumps(payload, sort_keys=True)

    forbidden = ["token=", "secret=", "password=", "Bearer ", "127.0.0.1", "10.", "192.168.", "postgresql://"]
    for term in forbidden:
        assert term not in serialized


def test_approved_replay_declaration_json_is_deterministic() -> None:
    assert approved_replay_provider_declarations_json() == approved_replay_provider_declarations_json()
    assert json.loads(approved_replay_provider_declarations_json()) == declaration_payload()
