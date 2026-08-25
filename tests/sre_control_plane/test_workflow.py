from __future__ import annotations

import json
from pathlib import Path

import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker

from sre_control_plane.contracts import InvestigationRequest
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.persistence import (
    AttemptRecord,
    AttemptTransitionRecord,
    Base,
    CapabilityCheckRecord,
    HumanReviewRecord,
    InvestigationResultRecord,
    RequestRecord,
    TaskRecord,
    TaskTransitionRecord,
)
from sre_control_plane.states import AttemptState, TaskState
from sre_control_plane.workflow import (
    DuplicateRequestConflict,
    HumanReviewDecision,
    HumanReviewRequest,
    InvalidStateTransition,
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
