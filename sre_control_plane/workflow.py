from __future__ import annotations

import hashlib
import json
import logging
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from sre_control_plane.contracts import (
    MVP_GITOPS_APPLICATION,
    MVP_NAMESPACE,
    MVP_ROLLOUT,
    MVP_WORKLOAD,
    REQUIRED_CAPABILITIES,
    InvestigationRequest,
)
from sre_control_plane.executor import (
    CapabilityReport,
    ExecutorStatus,
    InvestigationExecutor,
    StartInvestigationCommand,
)
from sre_control_plane.persistence import (
    AttemptRecord,
    AttemptTransitionRecord,
    CapabilityCheckRecord,
    ExecutorInvocationRecord,
    HumanReviewRecord,
    InvestigationResultRecord,
    RequestRecord,
    TaskRecord,
    TaskTransitionRecord,
)
from sre_control_plane.states import AttemptState, TaskState

LOGGER = logging.getLogger(__name__)

MUTATION_CAPABILITY_HINTS = (
    ".write",
    ".mutate",
    ".merge",
    ".close",
    ".execute",
    ".promote",
    ".abort",
    ".retry",
)

ALLOWED_TASK_TRANSITIONS: dict[str | None, set[str]] = {
    None: {TaskState.READY},
    TaskState.READY: {TaskState.RUNNING, TaskState.FAILED, TaskState.CANCELLED},
    TaskState.RUNNING: {
        TaskState.AWAITING_HUMAN_REVIEW,
        TaskState.READY,
        TaskState.FAILED,
        TaskState.TIMED_OUT,
        TaskState.CANCELLED,
    },
    TaskState.AWAITING_HUMAN_REVIEW: {
        TaskState.COMPLETED,
        TaskState.FAILED,
        TaskState.CANCELLED,
    },
}

ALLOWED_ATTEMPT_TRANSITIONS: dict[str | None, set[str]] = {
    None: {AttemptState.CREATED},
    AttemptState.CREATED: {AttemptState.CAPABILITY_CHECKED, AttemptState.CAPABILITY_REJECTED, AttemptState.CANCELLED},
    AttemptState.CAPABILITY_CHECKED: {AttemptState.DISPATCHED, AttemptState.DISPATCH_FAILED, AttemptState.CANCELLED},
    AttemptState.DISPATCHED: {AttemptState.RUNNING, AttemptState.FAILED, AttemptState.TIMED_OUT, AttemptState.STALE, AttemptState.CANCELLED},
    AttemptState.RUNNING: {AttemptState.SUCCEEDED, AttemptState.FAILED, AttemptState.TIMED_OUT, AttemptState.STALE, AttemptState.CANCELLED},
}


class WorkflowError(RuntimeError):
    pass


class DuplicateRequestConflict(WorkflowError):
    pass


class TaskNotFound(WorkflowError):
    pass


class InvalidStateTransition(WorkflowError):
    pass


class HumanReviewDecision(StrEnum):
    COMPLETE = "complete"
    REJECT = "reject"


class HumanReviewRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    decision: HumanReviewDecision
    actor: str = Field(min_length=1, max_length=128)
    rationale: str = Field(min_length=1, max_length=2000)
    github_reference: str | None = Field(default=None, max_length=512)


class TransitionView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    from_state: str | None
    to_state: str
    reason: str
    actor: str


class AttemptView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attempt_id: str
    state: str


class ResultView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    result_id: str
    status: str
    executor_id: str


class TaskView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: str
    task_id: str
    task_state: str
    attempt: AttemptView | None
    result: ResultView | None
    duplicate_submission: bool = False
    failure_reason: str | None = None
    task_transitions: list[TransitionView] = Field(default_factory=list)
    attempt_transitions: list[TransitionView] = Field(default_factory=list)


class SreInvestigationWorkflow:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        executor: InvestigationExecutor,
    ) -> None:
        self._session_factory = session_factory
        self._executor = executor

    def submit_request(self, request: InvestigationRequest) -> TaskView:
        payload = canonical_payload(request)

        with self._session_factory.begin() as session:
            existing = session.scalar(
                select(RequestRecord).where(RequestRecord.request_id == request.request_id)
            )
            if existing is not None:
                if canonical_json(existing.payload) != canonical_json(payload):
                    raise DuplicateRequestConflict("request_id already exists with a different payload")
                return self._task_view_for_request(session, existing, duplicate=True)

            request_record = RequestRecord(
                request_id=request.request_id,
                payload=payload,
                status="ACCEPTED",
            )
            task = TaskRecord(
                task_id=stable_id("task", request.request_id),
                request=request_record,
                state=TaskState.READY,
            )
            attempt = AttemptRecord(
                attempt_id=f"{task.task_id}-a1",
                task=task,
                state=AttemptState.CREATED,
                fencing_token=1,
            )
            session.add_all([request_record, task, attempt])
            session.flush()
            record_task_transition(session, task, None, TaskState.READY, "request_accepted", "control-plane")
            record_attempt_transition(session, attempt, None, AttemptState.CREATED, "attempt_created", "control-plane")

            capability_report = self._executor.describe_capabilities()
            capability_failure = capability_rejection_reason(capability_report)
            session.add(
                CapabilityCheckRecord(
                    attempt_id=attempt.id,
                    executor_id=capability_report.executor_id,
                    status="REJECTED" if capability_failure else "PASSED",
                    declared_capabilities={"items": capability_report.declared_capabilities},
                    denied_capabilities={"items": capability_report.denied_capabilities},
                    target_scope=capability_report.target_scope,
                    verification_evidence={"items": capability_report.verification_evidence},
                )
            )
            if capability_failure is not None:
                record_attempt_transition(
                    session,
                    attempt,
                    AttemptState.CREATED,
                    AttemptState.CAPABILITY_REJECTED,
                    capability_failure,
                    "control-plane",
                )
                return self._task_view_for_request(session, request_record, failure_reason=capability_failure)

            record_attempt_transition(
                session,
                attempt,
                AttemptState.CREATED,
                AttemptState.CAPABILITY_CHECKED,
                "capabilities_verified",
                "control-plane",
            )
            record_task_transition(session, task, TaskState.READY, TaskState.RUNNING, "fake_executor_started", "control-plane")
            invocation = ExecutorInvocationRecord(
                attempt_id=attempt.id,
                executor_id=capability_report.executor_id,
                operation="start_investigation",
                idempotency_key=attempt.attempt_id,
                fencing_token=1,
                status="INTENT_RECORDED",
            )
            session.add(invocation)

            command = StartInvestigationCommand(
                request=request,
                task_id=task.task_id,
                attempt_id=attempt.attempt_id,
                idempotency_key=attempt.attempt_id,
                fencing_token=1,
            )
            task_id = task.task_id
            attempt_id = attempt.attempt_id

        start_response = self._executor.start_investigation(command)
        result = self._executor.get_result(attempt_id, attempt_id)

        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id))
            if task is None or attempt is None:
                raise TaskNotFound("task or attempt disappeared during fake workflow execution")

            record_attempt_transition(
                session,
                attempt,
                AttemptState.CAPABILITY_CHECKED,
                AttemptState.DISPATCHED,
                "adapter_accepted_fake_dispatch",
                "control-plane",
            )
            record_attempt_transition(
                session,
                attempt,
                AttemptState.DISPATCHED,
                AttemptState.RUNNING,
                "fake_executor_running",
                "fake-executor",
            )
            if start_response.status != ExecutorStatus.SUCCEEDED:
                record_attempt_transition(
                    session,
                    attempt,
                    AttemptState.RUNNING,
                    AttemptState.FAILED,
                    "fake_executor_failed",
                    "control-plane",
                )
                record_task_transition(session, task, TaskState.RUNNING, TaskState.READY, "fake_executor_failed", "control-plane")
                return self._task_view(session, task, failure_reason="fake_executor_failed")

            record_attempt_transition(
                session,
                attempt,
                AttemptState.RUNNING,
                AttemptState.SUCCEEDED,
                "schema_valid_result",
                "control-plane",
            )
            persisted_result = InvestigationResultRecord(
                result_id=result.result_id,
                task_id=task.id,
                attempt_id=attempt.id,
                executor_id=result.executor_id,
                status=result.status,
                payload=result.model_dump(mode="json"),
            )
            session.add(persisted_result)
            record_task_transition(
                session,
                task,
                TaskState.RUNNING,
                TaskState.AWAITING_HUMAN_REVIEW,
                "schema_valid_result_requires_human_review",
                "control-plane",
            )
            return self._task_view(session, task)

    def get_task(self, task_id: str) -> TaskView:
        with self._session_factory() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            if task is None:
                raise TaskNotFound(f"task not found: {task_id}")
            return self._task_view(session, task)

    def record_human_review(self, task_id: str, review: HumanReviewRequest) -> TaskView:
        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            if task is None:
                raise TaskNotFound(f"task not found: {task_id}")
            if task.state != TaskState.AWAITING_HUMAN_REVIEW:
                raise InvalidStateTransition("human review is allowed only from AWAITING_HUMAN_REVIEW")

            attempt = latest_attempt(session, task)
            target_state = (
                TaskState.COMPLETED
                if review.decision == HumanReviewDecision.COMPLETE
                else TaskState.FAILED
            )
            session.add(
                HumanReviewRecord(
                    task_id=task.id,
                    attempt_id=attempt.id if attempt is not None else None,
                    actor=review.actor,
                    decision=review.decision,
                    rationale=review.rationale,
                    github_reference=review.github_reference,
                )
            )
            record_task_transition(
                session,
                task,
                TaskState.AWAITING_HUMAN_REVIEW,
                target_state,
                f"human_review_{review.decision}",
                review.actor,
            )
            return self._task_view(session, task)

    def _task_view_for_request(
        self,
        session: Session,
        request_record: RequestRecord,
        duplicate: bool = False,
        failure_reason: str | None = None,
    ) -> TaskView:
        task = session.scalar(
            select(TaskRecord)
            .where(TaskRecord.request_id == request_record.id)
            .order_by(TaskRecord.id.desc())
        )
        if task is None:
            raise TaskNotFound("task not found for request")
        return self._task_view(session, task, duplicate=duplicate, failure_reason=failure_reason)

    def _task_view(
        self,
        session: Session,
        task: TaskRecord,
        duplicate: bool = False,
        failure_reason: str | None = None,
    ) -> TaskView:
        request_record = session.get(RequestRecord, task.request_id)
        attempt = latest_attempt(session, task)
        result = latest_result(session, task)
        return TaskView(
            request_id=request_record.request_id if request_record else "",
            task_id=task.task_id,
            task_state=task.state,
            attempt=AttemptView(attempt_id=attempt.attempt_id, state=attempt.state) if attempt else None,
            result=(
                ResultView(
                    result_id=result.result_id,
                    status=result.status,
                    executor_id=result.executor_id,
                )
                if result
                else None
            ),
            duplicate_submission=duplicate,
            failure_reason=failure_reason,
            task_transitions=[
                TransitionView(
                    from_state=transition.from_state,
                    to_state=transition.to_state,
                    reason=transition.reason,
                    actor=transition.actor,
                )
                for transition in session.scalars(
                    select(TaskTransitionRecord)
                    .where(TaskTransitionRecord.task_id == task.id)
                    .order_by(TaskTransitionRecord.id)
                )
            ],
            attempt_transitions=[
                TransitionView(
                    from_state=transition.from_state,
                    to_state=transition.to_state,
                    reason=transition.reason,
                    actor=transition.actor,
                )
                for transition in (
                    session.scalars(
                        select(AttemptTransitionRecord)
                        .where(AttemptTransitionRecord.attempt_id == attempt.id)
                        .order_by(AttemptTransitionRecord.id)
                    )
                    if attempt
                    else []
                )
            ],
        )


def capability_rejection_reason(report: CapabilityReport) -> str | None:
    declared = set(report.declared_capabilities)
    missing = sorted(REQUIRED_CAPABILITIES - declared)
    excessive = sorted(declared - REQUIRED_CAPABILITIES)
    mutation_like = sorted(
        capability
        for capability in declared
        if any(hint in capability for hint in MUTATION_CAPABILITY_HINTS)
    )
    expected_scope = {
        "namespace": MVP_NAMESPACE,
        "workload": MVP_WORKLOAD,
        "rollout": MVP_ROLLOUT,
        "gitops_application": MVP_GITOPS_APPLICATION,
    }
    bad_scope = {
        key: value
        for key, value in report.target_scope.items()
        if expected_scope.get(key) != value
    }
    missing_scope = sorted(set(expected_scope) - set(report.target_scope))

    if missing:
        return "capability_missing:" + ",".join(missing)
    if excessive or mutation_like:
        return "capability_scope_invalid:" + ",".join(sorted(set(excessive + mutation_like)))
    if missing_scope or bad_scope:
        return "capability_scope_invalid"
    if "1.0" not in report.schema_versions:
        return "capability_missing:schema_version_1.0"
    if not (report.supports_idempotent_start or report.supports_status_lookup):
        return "capability_missing:idempotent_start_or_status_lookup"
    return None


def record_task_transition(
    session: Session,
    task: TaskRecord,
    from_state: str | None,
    to_state: str,
    reason: str,
    actor: str,
) -> None:
    assert_transition_allowed(ALLOWED_TASK_TRANSITIONS, from_state, to_state)
    task.state = to_state
    session.add(
        TaskTransitionRecord(
            task_id=task.id,
            from_state=from_state,
            to_state=to_state,
            reason=reason,
            actor=actor,
        )
    )
    log_lifecycle("task_transition", task_id=task.task_id, from_state=from_state, to_state=to_state, reason=reason, actor=actor)


def record_attempt_transition(
    session: Session,
    attempt: AttemptRecord,
    from_state: str | None,
    to_state: str,
    reason: str,
    actor: str,
) -> None:
    assert_transition_allowed(ALLOWED_ATTEMPT_TRANSITIONS, from_state, to_state)
    attempt.state = to_state
    session.add(
        AttemptTransitionRecord(
            attempt_id=attempt.id,
            from_state=from_state,
            to_state=to_state,
            reason=reason,
            actor=actor,
            fencing_token=attempt.fencing_token,
        )
    )
    log_lifecycle(
        "attempt_transition",
        attempt_id=attempt.attempt_id,
        from_state=from_state,
        to_state=to_state,
        reason=reason,
        actor=actor,
    )


def assert_transition_allowed(
    allowed: dict[str | None, set[str]],
    from_state: str | None,
    to_state: str,
) -> None:
    if to_state not in allowed.get(from_state, set()):
        raise InvalidStateTransition(f"transition {from_state} -> {to_state} is not permitted")


def latest_attempt(session: Session, task: TaskRecord) -> AttemptRecord | None:
    return session.scalar(
        select(AttemptRecord)
        .where(AttemptRecord.task_id == task.id)
        .order_by(AttemptRecord.id.desc())
    )


def latest_result(session: Session, task: TaskRecord) -> InvestigationResultRecord | None:
    return session.scalar(
        select(InvestigationResultRecord)
        .where(InvestigationResultRecord.task_id == task.id)
        .order_by(InvestigationResultRecord.id.desc())
    )


def canonical_payload(request: InvestigationRequest) -> dict:
    return request.model_dump(mode="json")


def canonical_json(payload: dict) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"))


def stable_id(prefix: Literal["task"], value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]
    return f"{prefix}-{digest}"


def log_lifecycle(event: str, **fields: str | None) -> None:
    LOGGER.info(json.dumps({"event": event, **fields}, sort_keys=True))
