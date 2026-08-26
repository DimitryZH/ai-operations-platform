from __future__ import annotations

import json
from pathlib import Path

import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker

from sre_control_plane.contracts import InvestigationRequest
from sre_control_plane.executor import ExecutorStatus, StartInvestigationResponse
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.persistence import (
    AttemptRecord,
    Base,
    CapabilityCheckRecord,
    InvestigationResultRecord,
    RetryDecisionRecord,
    TaskRecord,
)
from sre_control_plane.states import AttemptState, TaskState
from sre_control_plane.workflow import (
    DuplicateRequestConflict,
    DuplicateRetryConflict,
    HumanReviewDecision,
    HumanReviewRequest,
    InvalidStateTransition,
    RetryRequest,
    SreInvestigationWorkflow,
    StaleFencingToken,
)

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture()
def session_factory(tmp_path: Path):
    engine = create_engine(f"sqlite:///{tmp_path / 'workflow.db'}")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, expire_on_commit=False)


def request_example(request_id: str = "req-20260813-stage-001") -> InvestigationRequest:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    payload["request_id"] = request_id
    payload["signal"]["fingerprint"] = request_id
    return InvestigationRequest.model_validate(payload)


def count_records(session_factory, model) -> int:
    with session_factory() as session:
        return session.scalar(select(func.count()).select_from(model))


def test_intake_persists_ready_task_without_calling_executor(session_factory) -> None:
    executor = CountingExecutor()
    workflow = SreInvestigationWorkflow(session_factory, executor)

    view = workflow.submit_request(request_example())

    assert view.task_state == TaskState.READY
    assert view.attempt is None
    assert executor.start_count == 0
    assert count_records(session_factory, AttemptRecord) == 0


def test_tick_claims_one_ready_task_and_reaches_human_review(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())

    tick = workflow.run_dispatch_tick("tick-one")
    view = workflow.get_task(task.task_id)

    assert tick.dispatched is True
    assert tick.task_id == task.task_id
    assert tick.fencing_token == 1
    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.SUCCEEDED
    assert view.attempt_transitions[-1].fencing_token == 1
    assert view.task_transitions[-1].fencing_token == 1
    assert count_records(session_factory, CapabilityCheckRecord) == 1
    assert count_records(session_factory, InvestigationResultRecord) == 1


def test_ticks_claim_ready_tasks_in_creation_order(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    first = workflow.submit_request(request_example("request-first"))
    second = workflow.submit_request(request_example("request-second"))

    first_tick = workflow.run_dispatch_tick("tick-one")
    second_tick = workflow.run_dispatch_tick("tick-two")

    assert first_tick.task_id == first.task_id
    assert second_tick.task_id == second.task_id
    assert first_tick.fencing_token == 1
    assert second_tick.fencing_token == 2


def test_missing_capability_fails_closed_after_tick(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, MissingCapabilityExecutor())
    task = workflow.submit_request(request_example())

    tick = workflow.run_dispatch_tick("tick-capability")
    view = workflow.get_task(task.task_id)

    assert tick.dispatched is False
    assert tick.reason == "capability_missing:prometheus.query"
    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.CAPABILITY_REJECTED
    assert count_records(session_factory, CapabilityCheckRecord) == 1


def test_dispatch_failure_returns_task_to_ready_and_releases_lease(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FailedStartExecutor())
    task = workflow.submit_request(request_example())

    tick = workflow.run_dispatch_tick("tick-failure")
    view = workflow.get_task(task.task_id)

    assert tick.dispatched is True
    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.DISPATCH_FAILED
    subsequent_tick = workflow.run_dispatch_tick("tick-next")
    assert subsequent_tick.dispatched is False
    assert subsequent_tick.reason == "no_dispatch_eligible_task"
    assert [attempt.attempt_id for attempt in view.attempts] == [f"{task.task_id}-a1"]


def test_result_failure_returns_task_to_ready(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, ResultExceptionExecutor())
    task = workflow.submit_request(request_example())

    workflow.run_dispatch_tick("tick-result-failure")
    view = workflow.get_task(task.task_id)

    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.FAILED


def test_operator_retry_only_persists_ready_work_until_tick(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FailFirstStartExecutor())
    task = workflow.submit_request(request_example())
    workflow.run_dispatch_tick("tick-first")

    queued_retry = workflow.retry_task(
        task.task_id,
        RetryRequest(
            retry_id="retry-operator-001",
            actor="local-operator",
            rationale="Retry after deterministic fake dispatch failure.",
        ),
    )

    assert queued_retry.task_state == TaskState.READY
    assert queued_retry.attempt is not None
    assert queued_retry.attempt.attempt_id.endswith("-a1")
    assert count_records(session_factory, AttemptRecord) == 1

    tick = workflow.run_dispatch_tick("tick-retry")
    retried = workflow.get_task(task.task_id)
    assert tick.dispatched is True
    assert retried.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert retried.attempt is not None
    assert retried.attempt.attempt_id.endswith("-a2")
    with session_factory() as session:
        decision = session.scalar(select(RetryDecisionRecord))
    assert decision is not None
    assert decision.new_attempt_id is not None


def test_human_retry_only_persists_ready_work_until_tick(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())
    workflow.run_dispatch_tick("tick-first")

    queued_retry = workflow.record_human_review(
        task.task_id,
        HumanReviewRequest(
            decision=HumanReviewDecision.RETRY,
            retry_id="retry-human-001",
            actor="local-operator",
            rationale="Request another bounded investigation attempt.",
        ),
    )

    assert queued_retry.task_state == TaskState.READY
    assert len(queued_retry.attempts) == 1
    workflow.run_dispatch_tick("tick-human-retry")
    retried = workflow.get_task(task.task_id)
    assert retried.attempt is not None
    assert retried.attempt.attempt_id.endswith("-a2")


def test_duplicate_retry_is_idempotent_and_conflicting_payload_is_rejected(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FailedStartExecutor())
    task = workflow.submit_request(request_example())
    workflow.run_dispatch_tick("tick-first")
    retry = RetryRequest(
        retry_id="retry-duplicate-001",
        actor="local-operator",
        rationale="Retry after fake dispatch failure.",
    )

    workflow.retry_task(task.task_id, retry)
    duplicate = workflow.retry_task(task.task_id, retry)
    with pytest.raises(DuplicateRetryConflict):
        workflow.retry_task(
            task.task_id,
            retry.model_copy(update={"actor": "different-operator"}),
        )

    assert duplicate.duplicate_retry_submission is True
    assert count_records(session_factory, RetryDecisionRecord) == 1
    assert count_records(session_factory, AttemptRecord) == 1


def test_terminal_task_cannot_create_another_retry(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())
    workflow.run_dispatch_tick("tick-first")
    workflow.record_human_review(
        task.task_id,
        HumanReviewRequest(
            decision=HumanReviewDecision.COMPLETE,
            actor="local-operator",
            rationale="Accepted fake investigation result.",
        ),
    )

    with pytest.raises(InvalidStateTransition):
        workflow.retry_task(
            task.task_id,
            RetryRequest(
                retry_id="retry-terminal-001",
                actor="local-operator",
                rationale="Invalid retry after terminal closeout.",
            ),
        )


def test_tick_excludes_an_existing_active_attempt(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())
    with session_factory.begin() as session:
        persisted_task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task.task_id))
        session.add(
            AttemptRecord(
                attempt_id=f"{task.task_id}-active",
                task_id=persisted_task.id,
                state=AttemptState.RUNNING,
                fencing_token=99,
            )
        )

    tick = workflow.run_dispatch_tick("tick-blocked")
    assert tick.dispatched is False
    assert tick.reason == "active_attempt_exists"


def test_obsolete_fencing_token_cannot_persist_an_outcome(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())
    tick = workflow.run_dispatch_tick("tick-first")
    assert tick.attempt_id is not None
    assert tick.fencing_token is not None

    with pytest.raises(StaleFencingToken):
        workflow._record_result_failure(
            task.task_id,
            tick.attempt_id,
            "result_malformed:late_owner",
            "tick-first",
            tick.fencing_token,
        )

    assert workflow.get_task(task.task_id).task_state == TaskState.AWAITING_HUMAN_REVIEW


def test_same_request_id_with_different_payload_is_rejected(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    request = request_example()
    workflow.submit_request(request)
    changed = request.model_copy(
        update={"scenario": request.scenario.model_copy(update={"summary": "Different summary"})}
    )

    with pytest.raises(DuplicateRequestConflict):
        workflow.submit_request(changed)


class CountingExecutor(FakeInvestigationExecutor):
    def __init__(self) -> None:
        super().__init__()
        self.start_count = 0

    def start_investigation(self, command):
        self.start_count += 1
        return super().start_investigation(command)


class MissingCapabilityExecutor(FakeInvestigationExecutor):
    def describe_capabilities(self):
        report = super().describe_capabilities()
        return report.model_copy(
            update={
                "declared_capabilities": [
                    item for item in report.declared_capabilities if item != "prometheus.query"
                ]
            }
        )


class FailedStartExecutor(FakeInvestigationExecutor):
    def start_investigation(self, command):
        return StartInvestigationResponse(
            executor_id=self.executor_id,
            attempt_id=command.attempt_id,
            status=ExecutorStatus.FAILED,
            idempotency_key=command.idempotency_key,
            fencing_token=command.fencing_token,
        )


class FailFirstStartExecutor(FailedStartExecutor):
    def __init__(self) -> None:
        super().__init__()
        self.start_count = 0

    def start_investigation(self, command):
        self.start_count += 1
        if self.start_count == 1:
            return super().start_investigation(command)
        return FakeInvestigationExecutor.start_investigation(self, command)


class ResultExceptionExecutor(FakeInvestigationExecutor):
    def get_result(self, attempt_id: str, idempotency_key: str):
        raise ValueError("malformed fake result")
