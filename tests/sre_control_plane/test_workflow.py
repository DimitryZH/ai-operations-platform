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
    AttemptTransitionRecord,
    Base,
    CapabilityCheckRecord,
    HumanReviewRecord,
    InvestigationResultRecord,
    RequestRecord,
    RetryDecisionRecord,
    TaskRecord,
    TaskTransitionRecord,
)
from sre_control_plane.states import AttemptState, TaskState
from sre_control_plane.workflow import (
    DuplicateRequestConflict,
    HumanReviewDecision,
    HumanReviewRequest,
    InvalidStateTransition,
    RetryRequest,
    SreInvestigationWorkflow,
)

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture()
def session_factory(tmp_path: Path):
    engine = create_engine(f"sqlite:///{tmp_path / 'workflow.db'}")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, expire_on_commit=False)


def request_example() -> InvestigationRequest:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    return InvestigationRequest.model_validate(payload)


def count_records(session_factory, model) -> int:
    with session_factory() as session:
        return session.scalar(select(func.count()).select_from(model))


def test_valid_request_reaches_human_review_and_persists_records(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())

    view = workflow.submit_request(request_example())

    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.SUCCEEDED
    assert view.result is not None
    assert view.result.status == "succeeded"
    assert [transition.to_state for transition in view.task_transitions] == [
        TaskState.READY,
        TaskState.RUNNING,
        TaskState.AWAITING_HUMAN_REVIEW,
    ]
    assert [transition.to_state for transition in view.attempt_transitions] == [
        AttemptState.CREATED,
        AttemptState.CAPABILITY_CHECKED,
        AttemptState.DISPATCHED,
        AttemptState.RUNNING,
        AttemptState.SUCCEEDED,
    ]

    assert count_records(session_factory, RequestRecord) == 1
    assert count_records(session_factory, TaskRecord) == 1
    assert count_records(session_factory, AttemptRecord) == 1
    assert count_records(session_factory, InvestigationResultRecord) == 1
    assert count_records(session_factory, TaskTransitionRecord) == 3
    assert count_records(session_factory, AttemptTransitionRecord) == 5


def test_repeated_same_request_returns_existing_task_without_duplicate_work(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    first = workflow.submit_request(request_example())
    second = workflow.submit_request(request_example())

    assert second.duplicate_submission is True
    assert second.task_id == first.task_id
    assert second.attempt == first.attempt
    assert count_records(session_factory, RequestRecord) == 1
    assert count_records(session_factory, TaskRecord) == 1
    assert count_records(session_factory, AttemptRecord) == 1


def test_repeated_signal_fingerprint_returns_existing_task_without_duplicate_work(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    first = workflow.submit_request(request_example())
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    payload["request_id"] = "req-20260813-stage-002"
    repeated_event = InvestigationRequest.model_validate(payload)

    second = workflow.submit_request(repeated_event)

    assert second.duplicate_submission is True
    assert second.task_id == first.task_id
    assert second.attempt == first.attempt
    assert count_records(session_factory, RequestRecord) == 1
    assert count_records(session_factory, TaskRecord) == 1
    assert count_records(session_factory, AttemptRecord) == 1


def test_same_request_id_with_different_payload_is_rejected(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    workflow.submit_request(request_example())
    changed = request_example().model_copy(
        update={
            "scenario": request_example().scenario.model_copy(
                update={"summary": "Different valid summary"}
            )
        }
    )

    with pytest.raises(DuplicateRequestConflict):
        workflow.submit_request(changed)


def test_missing_fake_executor_capability_fails_closed(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, MissingCapabilityExecutor())

    view = workflow.submit_request(request_example())

    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.CAPABILITY_REJECTED
    assert view.result is None
    assert view.failure_reason == "capability_missing:prometheus.query"
    assert count_records(session_factory, CapabilityCheckRecord) == 1
    assert count_records(session_factory, InvestigationResultRecord) == 0


def test_excessive_fake_executor_capability_fails_closed(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, ExcessiveCapabilityExecutor())

    view = workflow.submit_request(request_example())

    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.CAPABILITY_REJECTED
    assert view.failure_reason == "capability_scope_invalid:kubernetes.write"


def test_failed_fake_executor_start_records_dispatch_failure(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FailedStartExecutor())

    view = workflow.submit_request(request_example())

    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.DISPATCH_FAILED
    assert view.result is None
    assert view.failure_reason == "dispatch_rejected:failed"
    assert [transition.to_state for transition in view.task_transitions] == [
        TaskState.READY,
        TaskState.RUNNING,
        TaskState.READY,
    ]
    assert [transition.to_state for transition in view.attempt_transitions] == [
        AttemptState.CREATED,
        AttemptState.CAPABILITY_CHECKED,
        AttemptState.DISPATCH_FAILED,
    ]


def test_result_exception_records_failed_attempt_and_ready_task(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, ResultExceptionExecutor())

    view = workflow.submit_request(request_example())

    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.FAILED
    assert view.result is None
    assert view.failure_reason == "result_malformed:ValueError"
    assert count_records(session_factory, InvestigationResultRecord) == 0


def test_mismatched_result_identity_records_failed_attempt(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, MismatchedResultExecutor())

    view = workflow.submit_request(request_example())

    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.FAILED
    assert view.result is None
    assert view.failure_reason == "result_malformed:task_id_mismatch"
    assert count_records(session_factory, InvestigationResultRecord) == 0


def test_operator_retry_creates_new_attempt_and_repeats_capability_verification(session_factory) -> None:
    executor = FailFirstStartExecutor()
    workflow = SreInvestigationWorkflow(session_factory, executor)
    failed = workflow.submit_request(request_example())

    retried = workflow.retry_task(
        failed.task_id,
        RetryRequest(
            retry_id="retry-operator-001",
            actor="local-operator",
            rationale="Retry after deterministic fake dispatch failure.",
        ),
    )

    assert failed.task_state == TaskState.READY
    assert failed.attempt is not None
    assert failed.attempt.state == AttemptState.DISPATCH_FAILED
    assert retried.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert retried.attempt is not None
    assert retried.attempt.attempt_id.endswith("-a2")
    assert retried.attempt.state == AttemptState.SUCCEEDED
    assert executor.capability_check_count == 2
    assert count_records(session_factory, AttemptRecord) == 2
    assert count_records(session_factory, CapabilityCheckRecord) == 2
    assert count_records(session_factory, RetryDecisionRecord) == 1
    assert count_records(session_factory, InvestigationResultRecord) == 1

    with session_factory() as session:
        attempts = list(session.scalars(select(AttemptRecord).order_by(AttemptRecord.id)))
        retry_decision = session.scalar(select(RetryDecisionRecord))
    assert [attempt.state for attempt in attempts] == [
        AttemptState.DISPATCH_FAILED,
        AttemptState.SUCCEEDED,
    ]
    assert attempts[0].attempt_id != attempts[1].attempt_id
    assert retry_decision is not None
    assert retry_decision.previous_attempt_id == attempts[0].id
    assert retry_decision.new_attempt_id == attempts[1].id


def test_operator_retry_after_failed_result_creates_new_attempt(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FailFirstResultExecutor())
    failed = workflow.submit_request(request_example())

    retried = workflow.retry_task(
        failed.task_id,
        RetryRequest(
            retry_id="retry-operator-result-001",
            actor="local-operator",
            rationale="Retry after malformed fake result.",
        ),
    )

    assert failed.task_state == TaskState.READY
    assert failed.attempt is not None
    assert failed.attempt.state == AttemptState.FAILED
    assert retried.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert retried.attempt is not None
    assert retried.attempt.attempt_id.endswith("-a2")
    assert count_records(session_factory, AttemptRecord) == 2
    assert count_records(session_factory, CapabilityCheckRecord) == 2
    assert count_records(session_factory, InvestigationResultRecord) == 1


def test_duplicate_operator_retry_does_not_create_another_attempt(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FailFirstStartExecutor())
    failed = workflow.submit_request(request_example())
    retry = RetryRequest(
        retry_id="retry-operator-duplicate-001",
        actor="local-operator",
        rationale="Retry once after fake dispatch failure.",
    )
    first_retry = workflow.retry_task(failed.task_id, retry)

    duplicate = workflow.retry_task(failed.task_id, retry)

    assert first_retry.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert duplicate.duplicate_retry_submission is True
    assert duplicate.attempt == first_retry.attempt
    assert count_records(session_factory, AttemptRecord) == 2
    assert count_records(session_factory, RetryDecisionRecord) == 1


def test_terminal_task_cannot_create_retry_attempt(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())
    completed = workflow.record_human_review(
        task.task_id,
        HumanReviewRequest(
            decision=HumanReviewDecision.COMPLETE,
            actor="local-operator",
            rationale="Accepted local fake investigation result.",
        ),
    )

    with pytest.raises(InvalidStateTransition):
        workflow.retry_task(
            completed.task_id,
            RetryRequest(
                retry_id="retry-terminal-001",
                actor="local-operator",
                rationale="Invalid retry after terminal closeout.",
            ),
        )

    assert count_records(session_factory, AttemptRecord) == 1
    assert count_records(session_factory, RetryDecisionRecord) == 0


def test_operator_retry_is_blocked_while_attempt_is_active(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FailFirstStartExecutor())
    failed = workflow.submit_request(request_example())
    with session_factory.begin() as session:
        task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == failed.task_id))
        attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.task_id == task.id))
        task.state = TaskState.READY
        attempt.state = AttemptState.RUNNING

    with pytest.raises(InvalidStateTransition):
        workflow.retry_task(
            failed.task_id,
            RetryRequest(
                retry_id="retry-active-001",
                actor="local-operator",
                rationale="Invalid retry while a previous attempt is still active.",
            ),
        )

    assert count_records(session_factory, AttemptRecord) == 1
    assert count_records(session_factory, RetryDecisionRecord) == 0


def test_human_retry_creates_new_attempt_and_preserves_reviewed_result(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())

    retried = workflow.record_human_review(
        task.task_id,
        HumanReviewRequest(
            decision=HumanReviewDecision.RETRY,
            retry_id="retry-human-001",
            actor="local-operator",
            rationale="Request another bounded investigation attempt.",
        ),
    )

    assert retried.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert retried.attempt is not None
    assert retried.attempt.attempt_id.endswith("-a2")
    assert retried.result is not None
    assert count_records(session_factory, AttemptRecord) == 2
    assert count_records(session_factory, InvestigationResultRecord) == 2
    assert count_records(session_factory, CapabilityCheckRecord) == 2
    assert count_records(session_factory, HumanReviewRecord) == 1
    assert count_records(session_factory, RetryDecisionRecord) == 1
    assert [transition.to_state for transition in retried.task_transitions] == [
        TaskState.READY,
        TaskState.RUNNING,
        TaskState.AWAITING_HUMAN_REVIEW,
        TaskState.READY,
        TaskState.RUNNING,
        TaskState.AWAITING_HUMAN_REVIEW,
    ]
    with session_factory() as session:
        attempts = list(session.scalars(select(AttemptRecord).order_by(AttemptRecord.id)))
        retry_decision = session.scalar(select(RetryDecisionRecord))
    assert retry_decision is not None
    assert retry_decision.previous_attempt_id == attempts[0].id
    assert retry_decision.new_attempt_id == attempts[1].id


def test_duplicate_human_retry_does_not_create_another_attempt_or_review(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())
    review = HumanReviewRequest(
        decision=HumanReviewDecision.RETRY,
        retry_id="retry-human-duplicate-001",
        actor="local-operator",
        rationale="Request another bounded investigation attempt.",
    )
    first_retry = workflow.record_human_review(task.task_id, review)

    duplicate = workflow.record_human_review(task.task_id, review)

    assert duplicate.duplicate_retry_submission is True
    assert duplicate.attempt == first_retry.attempt
    assert count_records(session_factory, AttemptRecord) == 2
    assert count_records(session_factory, HumanReviewRecord) == 1
    assert count_records(session_factory, RetryDecisionRecord) == 1


def test_human_can_complete_reviewed_task(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())

    reviewed = workflow.record_human_review(
        task.task_id,
        HumanReviewRequest(
            decision=HumanReviewDecision.COMPLETE,
            actor="local-operator",
            rationale="Accepted local fake investigation result.",
        ),
    )

    assert reviewed.task_state == TaskState.COMPLETED
    assert reviewed.task_transitions[-1].from_state == TaskState.AWAITING_HUMAN_REVIEW
    assert reviewed.task_transitions[-1].to_state == TaskState.COMPLETED
    assert count_records(session_factory, HumanReviewRecord) == 1


def test_human_can_reject_reviewed_task_without_retry(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())

    reviewed = workflow.record_human_review(
        task.task_id,
        HumanReviewRequest(
            decision=HumanReviewDecision.REJECT,
            actor="local-operator",
            rationale="Rejected fake result for local workflow validation.",
        ),
    )

    assert reviewed.task_state == TaskState.FAILED
    assert count_records(session_factory, AttemptRecord) == 1


def test_second_human_review_is_rejected_as_invalid_transition(session_factory) -> None:
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    task = workflow.submit_request(request_example())
    review = HumanReviewRequest(
        decision=HumanReviewDecision.COMPLETE,
        actor="local-operator",
        rationale="Accepted local fake investigation result.",
    )
    workflow.record_human_review(task.task_id, review)

    with pytest.raises(InvalidStateTransition):
        workflow.record_human_review(task.task_id, review)


class MissingCapabilityExecutor(FakeInvestigationExecutor):
    def describe_capabilities(self):
        report = super().describe_capabilities()
        return report.model_copy(
            update={
                "declared_capabilities": [
                    capability
                    for capability in report.declared_capabilities
                    if capability != "prometheus.query"
                ]
            }
        )


class ExcessiveCapabilityExecutor(FakeInvestigationExecutor):
    def describe_capabilities(self):
        report = super().describe_capabilities()
        return report.model_copy(
            update={
                "declared_capabilities": [
                    *report.declared_capabilities,
                    "kubernetes.write",
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


class FailFirstStartExecutor(FakeInvestigationExecutor):
    def __init__(self) -> None:
        super().__init__()
        self.capability_check_count = 0
        self.start_count = 0

    def describe_capabilities(self):
        self.capability_check_count += 1
        return super().describe_capabilities()

    def start_investigation(self, command):
        self.start_count += 1
        if self.start_count == 1:
            return StartInvestigationResponse(
                executor_id=self.executor_id,
                attempt_id=command.attempt_id,
                status=ExecutorStatus.FAILED,
                idempotency_key=command.idempotency_key,
                fencing_token=command.fencing_token,
            )
        return super().start_investigation(command)


class ResultExceptionExecutor(FakeInvestigationExecutor):
    def get_result(self, attempt_id: str, idempotency_key: str):
        raise ValueError("malformed fake result")


class FailFirstResultExecutor(FakeInvestigationExecutor):
    def __init__(self) -> None:
        super().__init__()
        self.result_count = 0

    def get_result(self, attempt_id: str, idempotency_key: str):
        self.result_count += 1
        if self.result_count == 1:
            raise ValueError("malformed fake result")
        return super().get_result(attempt_id, idempotency_key)


class MismatchedResultExecutor(FakeInvestigationExecutor):
    def get_result(self, attempt_id: str, idempotency_key: str):
        result = super().get_result(attempt_id, idempotency_key)
        return result.model_copy(update={"task_id": "task-wrong"})
