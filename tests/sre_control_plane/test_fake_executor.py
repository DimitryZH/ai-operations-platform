from __future__ import annotations

import json
from pathlib import Path

from sre_control_plane.contracts import REQUIRED_CAPABILITIES, InvestigationRequest, ResultStatus
from sre_control_plane.executor import ExecutorStatus, StartInvestigationCommand
from sre_control_plane.fake_executor import FakeInvestigationExecutor

ROOT = Path(__file__).resolve().parents[2]


def request_example() -> InvestigationRequest:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    return InvestigationRequest.model_validate(payload)


def test_fake_executor_declares_only_required_read_capabilities() -> None:
    report = FakeInvestigationExecutor().describe_capabilities()

    assert set(report.declared_capabilities) == REQUIRED_CAPABILITIES
    assert "kubernetes.write" in report.denied_capabilities
    assert report.supports_status_lookup is True


def test_fake_executor_start_is_idempotent_for_same_key() -> None:
    executor = FakeInvestigationExecutor()
    command = StartInvestigationCommand(
        request=request_example(),
        task_id="task-20260813-stage-001",
        attempt_id="attempt-20260813-stage-001-a1",
        idempotency_key="attempt-20260813-stage-001-a1",
        fencing_token=1,
    )

    first = executor.start_investigation(command)
    second = executor.start_investigation(command)

    assert first == second
    assert first.status is ExecutorStatus.SUCCEEDED


def test_fake_executor_returns_schema_valid_result() -> None:
    executor = FakeInvestigationExecutor()
    command = StartInvestigationCommand(
        request=request_example(),
        task_id="task-20260813-stage-001",
        attempt_id="attempt-20260813-stage-001-a1",
        idempotency_key="attempt-20260813-stage-001-a1",
        fencing_token=1,
    )
    executor.start_investigation(command)

    result = executor.get_result(command.attempt_id, command.idempotency_key)

    assert result.status is ResultStatus.SUCCEEDED
    assert result.executor_id == executor.executor_id
