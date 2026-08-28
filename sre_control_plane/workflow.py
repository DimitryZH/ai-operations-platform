from __future__ import annotations

import hashlib
import json
import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from pathlib import Path
from threading import Lock
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from sre_control_plane.contracts import (
    MVP_GITOPS_APPLICATION,
    MVP_NAMESPACE,
    MVP_ROLLOUT,
    MVP_WORKLOAD,
    REQUIRED_CAPABILITIES,
    InvestigationRequest,
    InvestigationResult,
    ResultStatus,
)
from sre_control_plane.evidence import (
    EVIDENCE_CONTENT_TYPE,
    EvidenceStore,
    EvidenceStoreError,
    LocalFilesystemEvidenceStore,
    StoredEvidence,
    build_evidence_package,
    validate_stored_evidence,
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
    DispatchLeaseRecord,
    EvidenceArtifactRecord,
    ExecutorInvocationRecord,
    GitHubPublicationRecord,
    HumanReviewRecord,
    InvestigationResultRecord,
    PublicationIntentRecord,
    RequestRecord,
    RetryDecisionRecord,
    TaskRecord,
    TaskTransitionRecord,
)
from sre_control_plane.publisher import (
    FakePublisher,
    PublicationRequest,
    PublicationError,
    Publisher,
)
from sre_control_plane.states import (
    ACTIVE_ATTEMPT_STATES,
    TERMINAL_ATTEMPT_STATES,
    TERMINAL_TASK_STATES,
    AttemptState,
    TaskState,
)

LOGGER = logging.getLogger(__name__)

DISPATCH_LEASE_NAME = "first_sre_dispatch"
DISPATCH_LEASE_DURATION = timedelta(seconds=30)

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
    TaskState.READY: {
        TaskState.RUNNING,
        TaskState.FAILED,
        TaskState.CANCELLED,
    },
    TaskState.RUNNING: {
        TaskState.AWAITING_HUMAN_REVIEW,
        TaskState.READY,
        TaskState.FAILED,
        TaskState.TIMED_OUT,
        TaskState.CANCELLED,
    },
    TaskState.AWAITING_HUMAN_REVIEW: {
        TaskState.COMPLETED,
        TaskState.READY,
        TaskState.FAILED,
        TaskState.CANCELLED,
    },
}

ALLOWED_ATTEMPT_TRANSITIONS: dict[str | None, set[str]] = {
    None: {AttemptState.CREATED},
    AttemptState.CREATED: {
        AttemptState.CAPABILITY_CHECKED,
        AttemptState.CAPABILITY_REJECTED,
        AttemptState.STALE,
        AttemptState.CANCELLED,
    },
    AttemptState.CAPABILITY_CHECKED: {
        AttemptState.DISPATCHED,
        AttemptState.DISPATCH_FAILED,
        AttemptState.STALE,
        AttemptState.CANCELLED,
    },
    AttemptState.DISPATCHED: {
        AttemptState.RUNNING,
        AttemptState.FAILED,
        AttemptState.TIMED_OUT,
        AttemptState.STALE,
        AttemptState.CANCELLED,
    },
    AttemptState.RUNNING: {
        AttemptState.SUCCEEDED,
        AttemptState.FAILED,
        AttemptState.TIMED_OUT,
        AttemptState.STALE,
        AttemptState.CANCELLED,
    },
}


class WorkflowError(RuntimeError):
    pass


class DuplicateRequestConflict(WorkflowError):
    pass


class DuplicateRetryConflict(WorkflowError):
    pass


class PublicationConflict(WorkflowError):
    pass


class TaskNotFound(WorkflowError):
    pass


class InvalidStateTransition(WorkflowError):
    pass


class StaleFencingToken(WorkflowError):
    pass


class HumanReviewDecision(StrEnum):
    COMPLETE = "complete"
    REJECT = "reject"
    RETRY = "retry"


class HumanReviewRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    decision: HumanReviewDecision
    actor: str = Field(min_length=1, max_length=128)
    rationale: str = Field(min_length=1, max_length=2000)
    github_reference: str | None = Field(default=None, max_length=512)
    retry_id: str | None = Field(default=None, min_length=1, max_length=128)

    @model_validator(mode="after")
    def validate_retry_id(self) -> "HumanReviewRequest":
        if self.decision == HumanReviewDecision.RETRY and self.retry_id is None:
            raise ValueError("retry_id is required when decision is retry")
        return self


class RetryRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    retry_id: str = Field(min_length=1, max_length=128)
    actor: str = Field(min_length=1, max_length=128)
    rationale: str = Field(min_length=1, max_length=2000)
    github_reference: str | None = Field(default=None, max_length=512)


class EvidencePublicationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    idempotency_key: str = Field(min_length=1, max_length=128)


class TransitionView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    from_state: str | None
    to_state: str
    reason: str
    actor: str
    fencing_token: int | None = None


class AttemptView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attempt_id: str
    state: str


class ResultView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    result_id: str
    status: str
    executor_id: str


class AttemptHistoryView(AttemptView):
    transitions: list[TransitionView] = Field(default_factory=list)


class ResultHistoryView(ResultView):
    attempt_id: str


class HumanReviewView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attempt_id: str | None
    actor: str
    decision: str
    rationale: str
    github_reference: str | None


class EvidenceArtifactView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attempt_id: str
    artifact_uri: str
    sha256: str
    content_type: str
    sanitization_status: str
    retention_policy: str


class PublicationHistoryView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attempt_id: str | None
    idempotency_key: str
    attempt_sequence: int
    payload_sha256: str
    status: str
    github_reference: str | None
    error_category: str | None


class CapabilityCheckHistoryView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attempt_id: str | None
    executor_id: str
    status: str


class ExecutorInvocationHistoryView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attempt_id: str
    executor_id: str
    operation: str
    idempotency_key: str
    fencing_token: int
    status: str
    error_category: str | None


class TaskView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: str
    task_id: str
    task_state: str
    attempt: AttemptView | None
    result: ResultView | None
    duplicate_submission: bool = False
    duplicate_retry_submission: bool = False
    failure_reason: str | None = None
    task_transitions: list[TransitionView] = Field(default_factory=list)
    attempt_transitions: list[TransitionView] = Field(default_factory=list)
    attempts: list[AttemptHistoryView] = Field(default_factory=list)
    results: list[ResultHistoryView] = Field(default_factory=list)
    reviews: list[HumanReviewView] = Field(default_factory=list)
    evidence_artifacts: list[EvidenceArtifactView] = Field(default_factory=list)
    publications: list[PublicationHistoryView] = Field(default_factory=list)
    capability_checks: list[CapabilityCheckHistoryView] = Field(default_factory=list)
    executor_invocations: list[ExecutorInvocationHistoryView] = Field(default_factory=list)


class DispatchTickRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lease_owner: str = Field(min_length=1, max_length=128)


class DispatchTickView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    dispatched: bool
    reason: str
    task_id: str | None = None
    attempt_id: str | None = None
    fencing_token: int | None = None


@dataclass(frozen=True)
class PreparedAttempt:
    command: StartInvestigationCommand
    task_id: str
    attempt_id: str
    executor_id: str


@dataclass(frozen=True)
class ClaimedAttempt:
    request: InvestigationRequest
    task_id: str
    attempt_id: str
    fencing_token: int


@dataclass(frozen=True)
class CapabilityRejectedAttempt:
    task_id: str
    failure_reason: str


@dataclass(frozen=True)
class ReconciliationClaim:
    task_id: str
    attempt_id: str
    executor_id: str | None
    idempotency_key: str | None
    fencing_token: int


class SreInvestigationWorkflow:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        executor: InvestigationExecutor,
        evidence_store: EvidenceStore | None = None,
        publisher: Publisher | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._executor = executor
        self._evidence_store = evidence_store or LocalFilesystemEvidenceStore(Path("var/evidence"))
        self._publisher = publisher or FakePublisher()
        self._dispatch_metrics = {
            "ticks_total": 0,
            "claims_total": 0,
            "lease_blocked_total": 0,
            "stale_fencing_total": 0,
            "reconciliations_total": 0,
            "reconciliation_stale_total": 0,
        }
        self._dispatch_metrics_lock = Lock()

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
            existing = find_request_by_fingerprint(session, request.signal.fingerprint)
            if existing is not None:
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
            session.add_all([request_record, task])
            session.flush()
            record_task_transition(session, task, None, TaskState.READY, "request_accepted", "control-plane")
            return self._task_view_for_request(session, request_record)

    def retry_task(self, task_id: str, retry: RetryRequest) -> TaskView:
        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            if task is None:
                raise TaskNotFound(f"task not found: {task_id}")

            existing = find_retry_decision(session, retry.retry_id)
            if existing is not None:
                assert_retry_decision_matches(
                    existing,
                    task_id=task.id,
                    actor=retry.actor,
                    rationale=retry.rationale,
                    source="operator_retry",
                    decision_type=HumanReviewDecision.RETRY,
                    github_reference=retry.github_reference,
                )
                return self._task_view(session, task, duplicate_retry=True)

            assert_task_can_retry(task)
            ensure_no_active_attempt(session)
            ensure_no_pending_retry_decision(session, task)
            previous_attempt = latest_attempt(session, task)
            if previous_attempt is None or previous_attempt.state not in TERMINAL_ATTEMPT_STATES:
                raise InvalidStateTransition("retry requires a terminal previous attempt")

            retry_decision = RetryDecisionRecord(
                retry_id=retry.retry_id,
                task_id=task.id,
                previous_attempt_id=previous_attempt.id,
                actor=retry.actor,
                rationale=retry.rationale,
                source="operator_retry",
                decision_type=HumanReviewDecision.RETRY,
                github_reference=retry.github_reference,
            )
            session.add(retry_decision)
            return self._task_view(session, task)

    def run_dispatch_tick(self, lease_owner: str) -> DispatchTickView:
        self._increment_dispatch_metric("ticks_total")
        reconciliation = self._claim_reconciliation(lease_owner)
        if isinstance(reconciliation, DispatchTickView):
            return reconciliation
        if reconciliation is not None:
            try:
                return self._reconcile_attempt(reconciliation, lease_owner)
            except StaleFencingToken:
                self._increment_dispatch_metric("stale_fencing_total")
                return DispatchTickView(
                    dispatched=False,
                    reason="stale_fencing_token_ignored",
                    task_id=reconciliation.task_id,
                    attempt_id=reconciliation.attempt_id,
                    fencing_token=reconciliation.fencing_token,
                )

        claimed: ClaimedAttempt | None = None

        with self._session_factory.begin() as session:
            now = utc_now()
            lease = lock_dispatch_lease(session, now)
            if lease_is_active(lease, now):
                self._increment_dispatch_metric("lease_blocked_total")
                return DispatchTickView(
                    dispatched=False,
                    reason="active_dispatch_lease",
                    task_id=lease_task_id(session, lease),
                    attempt_id=lease_attempt_id(session, lease),
                    fencing_token=lease.fencing_token,
                )
            active_attempt = session.scalar(
                select(AttemptRecord)
                .where(AttemptRecord.state.in_(ACTIVE_ATTEMPT_STATES))
                .with_for_update()
            )
            if active_attempt is not None:
                return DispatchTickView(
                    dispatched=False,
                    reason="active_attempt_exists",
                    attempt_id=active_attempt.attempt_id,
                )

            task = session.scalar(
                select(TaskRecord)
                .where(
                    TaskRecord.state == TaskState.READY,
                    or_(
                        ~select(AttemptRecord.id)
                        .where(AttemptRecord.task_id == TaskRecord.id)
                        .exists(),
                        select(RetryDecisionRecord.id)
                        .where(
                            RetryDecisionRecord.task_id == TaskRecord.id,
                            RetryDecisionRecord.new_attempt_id.is_(None),
                        )
                        .exists(),
                    ),
                )
                .order_by(TaskRecord.created_at, TaskRecord.id)
                .with_for_update()
            )
            if task is None:
                return DispatchTickView(dispatched=False, reason="no_dispatch_eligible_task")

            request_record = session.get(RequestRecord, task.request_id)
            if request_record is None:
                raise TaskNotFound("request not found for ready task")
            claim_dispatch_lease(lease, lease_owner, task.id, now)
            retry_decision = pending_retry_decision(session, task)
            claimed = self._claim_attempt(
                session,
                task,
                InvestigationRequest.model_validate(request_record.payload),
                attempt_created_reason="dispatcher_attempt_created",
                actor=f"dispatcher:{lease_owner}",
                fencing_token=lease.fencing_token,
                retry_decision=retry_decision,
            )
            attempt = session.scalar(
                select(AttemptRecord).where(AttemptRecord.attempt_id == claimed.attempt_id)
            )
            if attempt is None:
                raise TaskNotFound("claimed attempt disappeared before dispatch")
            lease.attempt_id = attempt.id
            lease.heartbeat_at = now
            self._increment_dispatch_metric("claims_total")
            log_lifecycle(
                "dispatch_claimed",
                task_id=task.task_id,
                attempt_id=attempt.attempt_id,
                lease_owner=lease_owner,
                fencing_token=str(lease.fencing_token),
            )

        if claimed is None:
            raise TaskNotFound("dispatcher did not claim an attempt")

        try:
            preparation = self._prepare_claimed_attempt(claimed, lease_owner)
        except StaleFencingToken:
            self._increment_dispatch_metric("stale_fencing_total")
            return DispatchTickView(
                dispatched=False,
                reason="stale_fencing_token_ignored",
                task_id=claimed.task_id,
                attempt_id=claimed.attempt_id,
                fencing_token=claimed.fencing_token,
            )

        if isinstance(preparation, CapabilityRejectedAttempt):
            return DispatchTickView(
                dispatched=False,
                reason=preparation.failure_reason,
                task_id=preparation.task_id,
                attempt_id=claimed.attempt_id,
                fencing_token=claimed.fencing_token,
            )

        try:
            self._run_prepared_attempt(preparation, lease_owner)
        except StaleFencingToken:
            self._increment_dispatch_metric("stale_fencing_total")
            return DispatchTickView(
                dispatched=False,
                reason="stale_fencing_token_ignored",
                task_id=preparation.task_id,
                attempt_id=preparation.attempt_id,
                fencing_token=preparation.command.fencing_token,
            )

        return DispatchTickView(
            dispatched=True,
            reason="attempt_executed",
            task_id=preparation.task_id,
            attempt_id=preparation.attempt_id,
            fencing_token=preparation.command.fencing_token,
        )

    def _claim_reconciliation(
        self,
        lease_owner: str,
    ) -> ReconciliationClaim | DispatchTickView | None:
        with self._session_factory.begin() as session:
            now = utc_now()
            lease = lock_dispatch_lease(session, now)
            if lease_is_active(lease, now):
                self._increment_dispatch_metric("lease_blocked_total")
                return DispatchTickView(
                    dispatched=False,
                    reason="active_dispatch_lease",
                    task_id=lease_task_id(session, lease),
                    attempt_id=lease_attempt_id(session, lease),
                    fencing_token=lease.fencing_token,
                )

            attempt: AttemptRecord | None = None
            task: TaskRecord | None = None
            if lease.attempt_id is not None:
                attempt = session.get(AttemptRecord, lease.attempt_id)
                task = session.get(TaskRecord, lease.task_id) if lease.task_id is not None else None
                if attempt is None or task is None or attempt.task_id != task.id:
                    release_dispatch_lease(lease, now)
                    return DispatchTickView(
                        dispatched=False,
                        reason="reconciliation_orphaned_lease",
                        fencing_token=lease.fencing_token,
                    )
            elif lease.task_id is not None:
                task_id = lease_task_id(session, lease)
                release_dispatch_lease(lease, now)
                return DispatchTickView(
                    dispatched=False,
                    reason="reconciliation_orphaned_lease",
                    task_id=task_id,
                    fencing_token=lease.fencing_token,
                )
            else:
                attempt = session.scalar(
                    select(AttemptRecord)
                    .where(AttemptRecord.state.in_(ACTIVE_ATTEMPT_STATES))
                    .order_by(AttemptRecord.id)
                    .with_for_update()
                )
                if attempt is None:
                    return None
                task = session.get(TaskRecord, attempt.task_id)
                if task is None:
                    raise TaskNotFound("active attempt has no parent task")

            if attempt.state in TERMINAL_ATTEMPT_STATES:
                release_dispatch_lease(lease, now)
                return DispatchTickView(
                    dispatched=False,
                    reason="reconciliation_terminal_lease_cleared",
                    task_id=task.task_id,
                    attempt_id=attempt.attempt_id,
                    fencing_token=lease.fencing_token,
                )

            invocation = session.scalar(
                select(ExecutorInvocationRecord)
                .where(ExecutorInvocationRecord.attempt_id == attempt.id)
                .order_by(ExecutorInvocationRecord.id.desc())
            )
            claim_reconciliation_lease(lease, lease_owner, task.id, attempt, now)
            self._increment_dispatch_metric("reconciliations_total")
            log_lifecycle(
                "reconciliation_claimed",
                task_id=task.task_id,
                attempt_id=attempt.attempt_id,
                lease_owner=lease_owner,
                fencing_token=str(lease.fencing_token),
            )
            return ReconciliationClaim(
                task_id=task.task_id,
                attempt_id=attempt.attempt_id,
                executor_id=invocation.executor_id if invocation is not None else None,
                idempotency_key=invocation.idempotency_key if invocation is not None else None,
                fencing_token=lease.fencing_token,
            )

    def _reconcile_attempt(
        self,
        claim: ReconciliationClaim,
        lease_owner: str,
    ) -> DispatchTickView:
        if claim.executor_id is None or claim.idempotency_key is None:
            self._record_reconciled_terminal(
                claim,
                lease_owner,
                AttemptState.STALE,
                "reconciliation_missing_invocation_identity",
            )
            return self._reconciliation_view(claim, "reconciliation_stale")

        try:
            raw_status = self._executor.get_status(claim.attempt_id, claim.idempotency_key)
            status = validate_attempt_status(raw_status)
            identity_failure = attempt_status_identity_failure(
                status,
                claim.attempt_id,
                claim.executor_id,
            )
        except Exception as exc:
            identity_failure = f"reconciliation_status_unavailable:{exc.__class__.__name__}"
            status = None

        if identity_failure is not None or status is None:
            self._record_reconciled_terminal(
                claim,
                lease_owner,
                AttemptState.STALE,
                identity_failure or "reconciliation_status_ambiguous",
            )
            return self._reconciliation_view(claim, "reconciliation_stale")

        if status.status in {ExecutorStatus.ACCEPTED, ExecutorStatus.QUEUED, ExecutorStatus.RUNNING}:
            self._record_reconciled_active(claim, lease_owner, status.status)
            return self._reconciliation_view(claim, "reconciliation_active_attempt")

        if status.status == ExecutorStatus.SUCCEEDED:
            try:
                raw_result = self._executor.get_result(claim.attempt_id, claim.idempotency_key)
                result = validate_investigation_result(raw_result)
                result_payload = result.model_dump(mode="json")
                result_failure = result_identity_failure(
                    result,
                    claim.task_id,
                    claim.attempt_id,
                    claim.executor_id,
                )
            except Exception as exc:
                result_failure = f"reconciliation_result_unavailable:{exc.__class__.__name__}"
                result = None
                result_payload = None
            if result_failure is not None or result is None or result_payload is None:
                self._record_reconciled_terminal(
                    claim,
                    lease_owner,
                    AttemptState.STALE,
                    result_failure or "reconciliation_result_ambiguous",
                )
                return self._reconciliation_view(claim, "reconciliation_stale")
            if result.status == ResultStatus.FAILED:
                self._record_reconciled_failed_result(claim, lease_owner, result, result_payload)
                return self._reconciliation_view(claim, "reconciliation_terminal")
            self._record_reconciled_success(claim, lease_owner, result, result_payload)
            return self._reconciliation_view(claim, "reconciliation_succeeded")

        if status.status == ExecutorStatus.DISPATCH_FAILED:
            self._record_reconciled_dispatch_failure(
                claim,
                lease_owner,
                "reconciliation_executor_dispatch_failed",
            )
            return self._reconciliation_view(claim, "reconciliation_terminal")

        terminal_state = {
            ExecutorStatus.FAILED: AttemptState.FAILED,
            ExecutorStatus.TIMED_OUT: AttemptState.TIMED_OUT,
            ExecutorStatus.STALE: AttemptState.STALE,
            ExecutorStatus.CANCELLED: AttemptState.CANCELLED,
        }.get(status.status)
        if terminal_state is None:
            terminal_state = AttemptState.STALE
            reason = "reconciliation_status_ambiguous"
        else:
            reason = f"reconciliation_executor_{status.status}"
        self._record_reconciled_terminal(claim, lease_owner, terminal_state, reason)
        return self._reconciliation_view(
            claim,
            "reconciliation_stale" if terminal_state == AttemptState.STALE else "reconciliation_terminal",
        )

    def _record_reconciled_dispatch_failure(
        self,
        claim: ReconciliationClaim,
        lease_owner: str,
        reason: str,
    ) -> None:
        with self._session_factory.begin() as session:
            task, attempt, lease = self._load_current_reconciliation(session, claim, lease_owner)
            if attempt.state != AttemptState.CAPABILITY_CHECKED:
                record_attempt_transition(
                    session,
                    attempt,
                    attempt.state,
                    AttemptState.STALE,
                    "reconciliation_dispatch_failure_state_ambiguous",
                    "control-plane",
                )
                update_invocation_status(
                    session,
                    attempt,
                    AttemptState.STALE,
                    "reconciliation_dispatch_failure_state_ambiguous",
                )
            else:
                record_attempt_transition(
                    session,
                    attempt,
                    AttemptState.CAPABILITY_CHECKED,
                    AttemptState.DISPATCH_FAILED,
                    reason,
                    "control-plane",
                )
                update_invocation_status(session, attempt, AttemptState.DISPATCH_FAILED, reason)
            if task.state == TaskState.RUNNING:
                record_task_transition(
                    session,
                    task,
                    TaskState.RUNNING,
                    TaskState.READY,
                    reason,
                    "control-plane",
                    fencing_token=claim.fencing_token,
                )
            release_dispatch_lease(lease, utc_now())

    def _record_reconciled_failed_result(
        self,
        claim: ReconciliationClaim,
        lease_owner: str,
        result: InvestigationResult,
        result_payload: dict,
    ) -> None:
        with self._session_factory.begin() as session:
            task, attempt, lease = self._load_current_reconciliation(session, claim, lease_owner)
            advance_attempt_to_running(session, attempt, "reconciliation_executor_failed_result")
            session.add(
                InvestigationResultRecord(
                    result_id=result.result_id,
                    task_id=task.id,
                    attempt_id=attempt.id,
                    executor_id=result.executor_id,
                    status=result.status,
                    payload=result_payload,
                )
            )
            record_attempt_transition(
                session,
                attempt,
                AttemptState.RUNNING,
                AttemptState.FAILED,
                "reconciliation_schema_valid_failed_result",
                "control-plane",
            )
            update_invocation_status(session, attempt, "RECONCILED_FAILED_RESULT")
            if task.state == TaskState.RUNNING:
                record_task_transition(
                    session,
                    task,
                    TaskState.RUNNING,
                    TaskState.READY,
                    "reconciliation_schema_valid_failed_result",
                    "control-plane",
                    fencing_token=claim.fencing_token,
                )
            release_dispatch_lease(lease, utc_now())

    def _record_reconciled_active(
        self,
        claim: ReconciliationClaim,
        lease_owner: str,
        status: ExecutorStatus,
    ) -> None:
        with self._session_factory.begin() as session:
            task, attempt, lease = self._load_current_reconciliation(session, claim, lease_owner)
            advance_attempt_to_running(session, attempt, "reconciliation_executor_active")
            update_invocation_status(session, attempt, f"RECONCILED_{status.upper()}")
            renew_dispatch_lease(lease, utc_now())
            log_lifecycle(
                "reconciliation_active",
                task_id=task.task_id,
                attempt_id=attempt.attempt_id,
                fencing_token=str(claim.fencing_token),
            )

    def _record_reconciled_success(
        self,
        claim: ReconciliationClaim,
        lease_owner: str,
        result,
        result_payload: dict,
    ) -> None:
        with self._session_factory.begin() as session:
            task, attempt, lease = self._load_current_reconciliation(session, claim, lease_owner)
            advance_attempt_to_running(session, attempt, "reconciliation_executor_succeeded")
            record_attempt_transition(
                session,
                attempt,
                AttemptState.RUNNING,
                AttemptState.SUCCEEDED,
                "reconciliation_schema_valid_result",
                "control-plane",
            )
            session.add(
                InvestigationResultRecord(
                    result_id=result.result_id,
                    task_id=task.id,
                    attempt_id=attempt.id,
                    executor_id=result.executor_id,
                    status=result.status,
                    payload=result_payload,
                )
            )
            update_invocation_status(session, attempt, "RECONCILED_SUCCEEDED")
            if task.state == TaskState.RUNNING:
                record_task_transition(
                    session,
                    task,
                    TaskState.RUNNING,
                    TaskState.AWAITING_HUMAN_REVIEW,
                    "reconciliation_schema_valid_result_requires_human_review",
                    "control-plane",
                    fencing_token=claim.fencing_token,
                )
            release_dispatch_lease(lease, utc_now())

    def _record_reconciled_terminal(
        self,
        claim: ReconciliationClaim,
        lease_owner: str,
        terminal_state: AttemptState,
        reason: str,
    ) -> None:
        with self._session_factory.begin() as session:
            task, attempt, lease = self._load_current_reconciliation(session, claim, lease_owner)
            if attempt.state == AttemptState.CAPABILITY_CHECKED and terminal_state != AttemptState.STALE:
                advance_attempt_to_running(session, attempt, "reconciliation_confirmed_invocation")
            elif attempt.state == AttemptState.DISPATCHED and terminal_state != AttemptState.STALE:
                advance_attempt_to_running(session, attempt, "reconciliation_confirmed_invocation")
            if attempt.state not in TERMINAL_ATTEMPT_STATES:
                record_attempt_transition(
                    session,
                    attempt,
                    attempt.state,
                    terminal_state,
                    reason,
                    "control-plane",
                )
            update_invocation_status(session, attempt, terminal_state, reason)
            if task.state == TaskState.RUNNING:
                record_task_transition(
                    session,
                    task,
                    TaskState.RUNNING,
                    TaskState.READY,
                    reason,
                    "control-plane",
                    fencing_token=claim.fencing_token,
                )
            release_dispatch_lease(lease, utc_now())
            if terminal_state == AttemptState.STALE:
                self._increment_dispatch_metric("reconciliation_stale_total")
            log_lifecycle(
                "reconciliation_terminal",
                task_id=task.task_id,
                attempt_id=attempt.attempt_id,
                terminal_state=terminal_state,
                reason=reason,
                fencing_token=str(claim.fencing_token),
            )

    def _load_current_reconciliation(
        self,
        session: Session,
        claim: ReconciliationClaim,
        lease_owner: str,
    ) -> tuple[TaskRecord, AttemptRecord, DispatchLeaseRecord]:
        task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == claim.task_id))
        attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == claim.attempt_id))
        if task is None or attempt is None:
            raise TaskNotFound("reconciliation task or attempt disappeared")
        lease = assert_current_dispatch_lease(
            session,
            task,
            attempt,
            lease_owner,
            claim.fencing_token,
        )
        return task, attempt, lease

    @staticmethod
    def _reconciliation_view(claim: ReconciliationClaim, reason: str) -> DispatchTickView:
        return DispatchTickView(
            dispatched=False,
            reason=reason,
            task_id=claim.task_id,
            attempt_id=claim.attempt_id,
            fencing_token=claim.fencing_token,
        )

    def dispatch_metrics(self) -> dict[str, int]:
        with self._dispatch_metrics_lock:
            return dict(self._dispatch_metrics)

    def publication_metrics(self) -> dict[str, int]:
        return self._publisher.metrics()

    def _increment_dispatch_metric(self, name: str) -> None:
        with self._dispatch_metrics_lock:
            self._dispatch_metrics[name] += 1

    def _claim_attempt(
        self,
        session: Session,
        task: TaskRecord,
        request: InvestigationRequest,
        attempt_created_reason: str,
        actor: str,
        fencing_token: int,
        retry_decision: RetryDecisionRecord | None = None,
    ) -> ClaimedAttempt:
        attempt_number = count_attempts(session, task) + 1
        attempt = AttemptRecord(
            attempt_id=f"{task.task_id}-a{attempt_number}",
            task=task,
            state=AttemptState.CREATED,
            fencing_token=fencing_token,
        )
        session.add(attempt)
        session.flush()
        if retry_decision is not None:
            retry_decision.new_attempt_id = attempt.id
        record_attempt_transition(session, attempt, None, AttemptState.CREATED, attempt_created_reason, actor)

        return ClaimedAttempt(
            request=request,
            task_id=task.task_id,
            attempt_id=attempt.attempt_id,
            fencing_token=fencing_token,
        )

    def _prepare_claimed_attempt(
        self,
        claimed: ClaimedAttempt,
        lease_owner: str,
    ) -> PreparedAttempt | CapabilityRejectedAttempt:
        try:
            capability_report = self._executor.describe_capabilities()
            capability_failure = capability_rejection_reason(capability_report)
        except Exception as exc:
            capability_report = None
            capability_failure = f"capability_verification_failed:{exc.__class__.__name__}"

        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == claimed.task_id))
            attempt = session.scalar(
                select(AttemptRecord).where(AttemptRecord.attempt_id == claimed.attempt_id)
            )
            if task is None or attempt is None:
                raise TaskNotFound("claimed task or attempt disappeared before capability verification")
            lease = assert_current_dispatch_lease(
                session,
                task,
                attempt,
                lease_owner,
                claimed.fencing_token,
            )
            renew_dispatch_lease(lease, utc_now())

            if capability_report is None:
                session.add(
                    CapabilityCheckRecord(
                        attempt_id=attempt.id,
                        executor_id="unverified",
                        status="REJECTED",
                        declared_capabilities={"items": []},
                        denied_capabilities={"items": []},
                        target_scope={},
                        verification_evidence={"items": [capability_failure]},
                    )
                )
                record_attempt_transition(
                    session,
                    attempt,
                    AttemptState.CREATED,
                    AttemptState.CAPABILITY_REJECTED,
                    capability_failure,
                    "control-plane",
                )
                release_dispatch_lease(lease, utc_now())
                return CapabilityRejectedAttempt(
                    task_id=task.task_id,
                    failure_reason=capability_failure,
                )

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
                release_dispatch_lease(lease, utc_now())
                return CapabilityRejectedAttempt(task_id=task.task_id, failure_reason=capability_failure)

            record_attempt_transition(
                session,
                attempt,
                AttemptState.CREATED,
                AttemptState.CAPABILITY_CHECKED,
                "capabilities_verified",
                "control-plane",
            )
            record_task_transition(
                session,
                task,
                TaskState.READY,
                TaskState.RUNNING,
                "dispatcher_claimed_ready_task",
                f"dispatcher:{lease_owner}",
                fencing_token=claimed.fencing_token,
            )
            invocation = ExecutorInvocationRecord(
                attempt_id=attempt.id,
                executor_id=capability_report.executor_id,
                operation="start_investigation",
                idempotency_key=attempt.attempt_id,
                fencing_token=claimed.fencing_token,
                status="INTENT_RECORDED",
            )
            session.add(invocation)

            return PreparedAttempt(
                command=StartInvestigationCommand(
                    request=claimed.request,
                    task_id=task.task_id,
                    attempt_id=attempt.attempt_id,
                    idempotency_key=attempt.attempt_id,
                    fencing_token=claimed.fencing_token,
                ),
                task_id=task.task_id,
                attempt_id=attempt.attempt_id,
                executor_id=capability_report.executor_id,
            )

    def _run_prepared_attempt(self, prepared: PreparedAttempt, lease_owner: str) -> TaskView:
        command = prepared.command
        task_id = prepared.task_id
        attempt_id = prepared.attempt_id

        try:
            start_response = self._executor.start_investigation(command)
        except Exception as exc:
            return self._record_dispatch_failure(
                task_id,
                attempt_id,
                f"dispatch_rejected:{exc.__class__.__name__}",
                lease_owner,
                command.fencing_token,
            )

        if (
            start_response.executor_id != prepared.executor_id
            or start_response.attempt_id != attempt_id
            or start_response.idempotency_key != attempt_id
            or start_response.fencing_token != command.fencing_token
        ):
            return self._record_dispatch_failure(
                task_id,
                attempt_id,
                "dispatch_rejected:identity_mismatch",
                lease_owner,
                command.fencing_token,
            )
        if start_response.status != ExecutorStatus.SUCCEEDED:
            return self._record_dispatch_failure(
                task_id,
                attempt_id,
                f"dispatch_rejected:{start_response.status}",
                lease_owner,
                command.fencing_token,
            )

        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id))
            if task is None or attempt is None:
                raise TaskNotFound("task or attempt disappeared during fake workflow execution")
            lease = assert_current_dispatch_lease(
                session,
                task,
                attempt,
                lease_owner,
                command.fencing_token,
            )
            renew_dispatch_lease(lease, utc_now())
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
            update_invocation_status(session, attempt, start_response.status)

        try:
            result = self._executor.get_result(attempt_id, attempt_id)
            normalized_result_payload = result.model_dump(mode="json")
            identity_failure = result_identity_failure(result, task_id, attempt_id, start_response.executor_id)
        except Exception as exc:
            return self._record_result_failure(
                task_id,
                attempt_id,
                f"result_malformed:{exc.__class__.__name__}",
                lease_owner,
                command.fencing_token,
            )

        if identity_failure is not None:
            return self._record_result_failure(
                task_id,
                attempt_id,
                identity_failure,
                lease_owner,
                command.fencing_token,
            )

        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id))
            if task is None or attempt is None:
                raise TaskNotFound("task or attempt disappeared during fake workflow execution")
            lease = assert_current_dispatch_lease(
                session,
                task,
                attempt,
                lease_owner,
                command.fencing_token,
            )
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
                payload=normalized_result_payload,
            )
            session.add(persisted_result)
            record_task_transition(
                session,
                task,
                TaskState.RUNNING,
                TaskState.AWAITING_HUMAN_REVIEW,
                "schema_valid_result_requires_human_review",
                "control-plane",
                fencing_token=command.fencing_token,
            )
            release_dispatch_lease(lease, utc_now())
            return self._task_view(session, task)

    def _record_dispatch_failure(
        self,
        task_id: str,
        attempt_id: str,
        reason: str,
        lease_owner: str,
        fencing_token: int,
    ) -> TaskView:
        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id))
            if task is None or attempt is None:
                raise TaskNotFound("task or attempt disappeared during dispatch failure handling")
            lease = assert_current_dispatch_lease(
                session,
                task,
                attempt,
                lease_owner,
                fencing_token,
            )
            record_attempt_transition(
                session,
                attempt,
                AttemptState.CAPABILITY_CHECKED,
                AttemptState.DISPATCH_FAILED,
                reason,
                "control-plane",
            )
            update_invocation_status(session, attempt, "DISPATCH_FAILED", reason)
            record_task_transition(
                session,
                task,
                TaskState.RUNNING,
                TaskState.READY,
                reason,
                "control-plane",
                fencing_token=fencing_token,
            )
            release_dispatch_lease(lease, utc_now())
            return self._task_view(session, task, failure_reason=reason)

    def _record_result_failure(
        self,
        task_id: str,
        attempt_id: str,
        reason: str,
        lease_owner: str,
        fencing_token: int,
    ) -> TaskView:
        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id))
            if task is None or attempt is None:
                raise TaskNotFound("task or attempt disappeared during result failure handling")
            lease = assert_current_dispatch_lease(
                session,
                task,
                attempt,
                lease_owner,
                fencing_token,
            )
            record_attempt_transition(
                session,
                attempt,
                AttemptState.RUNNING,
                AttemptState.FAILED,
                reason,
                "control-plane",
            )
            update_invocation_status(session, attempt, "FAILED", reason)
            record_task_transition(
                session,
                task,
                TaskState.RUNNING,
                TaskState.READY,
                reason,
                "control-plane",
                fencing_token=fencing_token,
            )
            release_dispatch_lease(lease, utc_now())
            return self._task_view(session, task, failure_reason=reason)

    def publish_evidence(
        self,
        task_id: str,
        request: EvidencePublicationRequest,
    ) -> TaskView:
        """Package and publish completed fake evidence without mutating workflow state."""
        with self._session_factory() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            if task is None:
                raise TaskNotFound(f"task not found: {task_id}")
            attempt, result, package_payload = self._publication_snapshot(session, task)

        # Persist the intent and acquire its durable claim before any adapter call.
        package_hash = hashlib.sha256(canonical_json(package_payload).encode("utf-8")).hexdigest()
        claim = self._claim_publication(
            task_id, attempt.attempt_id, request.idempotency_key, package_hash
        )
        if claim is None:
            return self.get_task(task_id)
        claim_token, publication_id = claim

        try:
            package = build_evidence_package(package_payload)
            stored = self._store_evidence(attempt.attempt_id, package)
            publication_payload = publication_payload_for_result(result.payload, stored.artifact_uri)
            payload_sha256 = hashlib.sha256(canonical_json(publication_payload).encode("utf-8")).hexdigest()
            self._set_publication_payload_hash(publication_id, claim_token, payload_sha256)
            receipt = self._publisher.validate_receipt(
                self._publisher.publish(
                    PublicationRequest(
                        idempotency_key=request.idempotency_key,
                        payload_sha256=payload_sha256,
                        payload=publication_payload,
                    )
                )
            )
        except Exception as exc:
            error_category = (
                exc.error_category if isinstance(exc, PublicationError) else type(exc).__name__[:64]
            )
            return self._finalize_publication(
                task_id, publication_id, claim_token, "FAILED", None,
                error_category, "publication_failed_retryable",
            )

        return self._finalize_publication(
            task_id, publication_id, claim_token, "PUBLISHED", receipt.reference, None, None
        )

    def _set_publication_payload_hash(
        self, publication_id: int, claim_token: str, payload_sha256: str
    ) -> None:
        with self._session_factory.begin() as session:
            publication = session.get(GitHubPublicationRecord, publication_id)
            if publication is None:
                raise TaskNotFound("publication disappeared before publisher invocation")
            intent = session.get(PublicationIntentRecord, publication.publication_intent_id)
            if intent is None or intent.active_claim_token != claim_token:
                raise PublicationConflict("publication claim was superseded before publisher invocation")
            publication.payload_sha256 = payload_sha256

    def _claim_publication(
        self, task_id: str, attempt_id: str, idempotency_key: str, payload_sha256: str
    ) -> tuple[str, int] | None:
        """Create or lock a logical publication; external work is deliberately outside this transaction."""
        for _ in range(2):
            try:
                with self._session_factory.begin() as session:
                    task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
                    attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id))
                    if task is None or attempt is None:
                        raise TaskNotFound("task or attempt disappeared during publication")
                    intent = session.scalar(
                        select(PublicationIntentRecord)
                        .where(PublicationIntentRecord.idempotency_key == idempotency_key)
                        .with_for_update()
                    )
                    if intent is None:
                        intent = PublicationIntentRecord(
                            task_id=task.id, attempt_id=attempt.id,
                            idempotency_key=idempotency_key, payload_sha256=payload_sha256,
                            status="PENDING", fencing_token=0, active_claim_token=None,
                            github_reference=None,
                        )
                        session.add(intent)
                        session.flush()
                    elif (
                        intent.task_id != task.id or intent.attempt_id != attempt.id
                        or intent.payload_sha256 != payload_sha256
                    ):
                        raise PublicationConflict(
                            "publication idempotency_key already exists with different semantics"
                        )
                    if intent.status == "PUBLISHED" or intent.active_claim_token is not None:
                        return None
                    intent.fencing_token += 1
                    claim_token = uuid.uuid4().hex
                    intent.active_claim_token = claim_token
                    sequence = (session.scalar(
                        select(func.max(GitHubPublicationRecord.attempt_sequence)).where(
                            GitHubPublicationRecord.publication_intent_id == intent.id
                        )
                    ) or 0) + 1
                    publication = GitHubPublicationRecord(
                        task_id=task.id, attempt_id=attempt.id, publication_intent_id=intent.id,
                        idempotency_key=idempotency_key, attempt_sequence=sequence,
                        payload_sha256=payload_sha256, github_reference=None, status="PENDING",
                        error_category=None,
                    )
                    session.add(publication)
                    session.flush()
                    return claim_token, publication.id
            except IntegrityError:
                # A competing creator won the intent unique key; read it on the next iteration.
                continue
        raise PublicationConflict("publication intent could not be claimed safely")

    def _finalize_publication(
        self, task_id: str, publication_id: int, claim_token: str, status: str,
        reference: str | None, error_category: str | None, failure_reason: str | None,
    ) -> TaskView:
        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            publication = session.get(GitHubPublicationRecord, publication_id)
            if task is None or publication is None:
                raise TaskNotFound("task or publication disappeared during completion handling")
            intent = session.scalar(
                select(PublicationIntentRecord)
                .where(PublicationIntentRecord.id == publication.publication_intent_id)
                .with_for_update()
            )
            if intent is None:
                raise TaskNotFound("publication intent disappeared during completion handling")
            if intent.active_claim_token != claim_token or intent.status == "PUBLISHED":
                return self._task_view(session, task)
            publication.status = status
            publication.github_reference = reference
            publication.error_category = error_category
            intent.active_claim_token = None
            intent.status = status
            if status == "PUBLISHED":
                intent.github_reference = reference
            return self._task_view(session, task, failure_reason=failure_reason)

    def _store_evidence(self, attempt_id: str, package) -> StoredEvidence:
        with self._session_factory() as session:
            attempt = session.scalar(select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id))
            if attempt is None:
                raise TaskNotFound(f"attempt not found: {attempt_id}")
            existing = session.scalar(
                select(EvidenceArtifactRecord).where(EvidenceArtifactRecord.attempt_id == attempt.id)
            )
            if existing is not None:
                if existing.sha256 != package.sha256:
                    raise PublicationConflict("attempt already has evidence with different content")
                return StoredEvidence(
                    artifact_uri=existing.artifact_uri,
                    sha256=existing.sha256,
                    content_type=existing.content_type,
                    sanitization_status=existing.sanitization_status,
                    retention_policy=existing.retention_policy,
                )

        stored = validate_stored_evidence(self._evidence_store.store(package), package)
        try:
            with self._session_factory.begin() as session:
                attempt = session.scalar(
                    select(AttemptRecord).where(AttemptRecord.attempt_id == attempt_id)
                )
                if attempt is None:
                    raise TaskNotFound(f"attempt not found: {attempt_id}")
                existing = session.scalar(
                    select(EvidenceArtifactRecord).where(EvidenceArtifactRecord.attempt_id == attempt.id)
                )
                if existing is not None:
                    if existing.sha256 != package.sha256:
                        raise PublicationConflict("attempt already has evidence with different content")
                    return StoredEvidence(
                        existing.artifact_uri, existing.sha256, existing.content_type,
                        existing.sanitization_status, existing.retention_policy,
                    )
                session.add(
                    EvidenceArtifactRecord(
                        attempt_id=attempt.id,
                        artifact_uri=stored.artifact_uri,
                        sha256=stored.sha256,
                        content_type=stored.content_type,
                        sanitization_status=stored.sanitization_status,
                        retention_policy=stored.retention_policy,
                    )
                )
                session.flush()
        except IntegrityError:
            with self._session_factory() as session:
                existing = session.scalar(
                    select(EvidenceArtifactRecord).join(AttemptRecord).where(
                        AttemptRecord.attempt_id == attempt_id
                    )
                )
                if existing is None or existing.sha256 != package.sha256:
                    raise PublicationConflict("concurrent evidence artifact has different content")
                return StoredEvidence(
                    existing.artifact_uri, existing.sha256, existing.content_type,
                    existing.sanitization_status, existing.retention_policy,
                )
        return stored

    def _publication_snapshot(
        self, session: Session, task: TaskRecord
    ) -> tuple[AttemptRecord, InvestigationResultRecord, dict]:
        attempt = latest_attempt(session, task)
        if attempt is None or attempt.state != AttemptState.SUCCEEDED:
            raise InvalidStateTransition("evidence publication requires a succeeded attempt")
        result = session.scalar(
            select(InvestigationResultRecord).where(InvestigationResultRecord.attempt_id == attempt.id)
        )
        if result is None or result.status not in {ResultStatus.SUCCEEDED, ResultStatus.PARTIAL}:
            raise InvalidStateTransition("evidence publication requires a succeeded or partial result")
        normalized_result = InvestigationResult.model_validate(result.payload).model_dump(mode="json")
        request = session.get(RequestRecord, task.request_id)
        if request is None:
            raise TaskNotFound("request not found for evidence publication")
        return attempt, result, {
            "schema_version": "1.0",
            "package_type": "sre_investigation_evidence",
            "request": request.payload,
            "task": {
                "task_id": task.task_id,
                "state": task.state,
                "timeline": timeline_payload(session, TaskTransitionRecord, "task_id", task.id),
            },
            "attempt": {
                "attempt_id": attempt.attempt_id,
                "state": attempt.state,
                "timeline": timeline_payload(session, AttemptTransitionRecord, "attempt_id", attempt.id),
                "capability_checks": capability_payload(session, attempt.id),
                "executor_invocations": invocation_payload(session, attempt.id),
            },
            "result": normalized_result,
        }

    def get_task(self, task_id: str) -> TaskView:
        with self._session_factory() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            if task is None:
                raise TaskNotFound(f"task not found: {task_id}")
            return self._task_view(session, task)

    def record_human_review(self, task_id: str, review: HumanReviewRequest) -> TaskView:
        if review.decision == HumanReviewDecision.RETRY:
            return self._record_human_retry(task_id, review)

        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            if task is None:
                raise TaskNotFound(f"task not found: {task_id}")
            if review.retry_id is not None:
                existing = find_retry_decision(session, review.retry_id)
                if existing is not None:
                    assert_retry_decision_matches(
                        existing,
                        task_id=task.id,
                        actor=review.actor,
                        rationale=review.rationale,
                        source="human_review_retry",
                        decision_type=review.decision,
                        github_reference=review.github_reference,
                    )
                raise InvalidStateTransition(
                    "retry_id is only valid when the human review decision is retry"
                )
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

    def _record_human_retry(self, task_id: str, review: HumanReviewRequest) -> TaskView:
        retry_id = review.retry_id
        if retry_id is None:
            raise InvalidStateTransition("retry_id is required when decision is retry")

        with self._session_factory.begin() as session:
            task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task_id))
            if task is None:
                raise TaskNotFound(f"task not found: {task_id}")

            existing = find_retry_decision(session, retry_id)
            if existing is not None:
                assert_retry_decision_matches(
                    existing,
                    task_id=task.id,
                    actor=review.actor,
                    rationale=review.rationale,
                    source="human_review_retry",
                    decision_type=review.decision,
                    github_reference=review.github_reference,
                )
                return self._task_view(session, task, duplicate_retry=True)

            if task.state != TaskState.AWAITING_HUMAN_REVIEW:
                raise InvalidStateTransition(
                    "human retry is allowed only from AWAITING_HUMAN_REVIEW"
                )
            ensure_no_active_attempt(session)
            ensure_no_pending_retry_decision(session, task)

            previous_attempt = latest_attempt(session, task)
            if previous_attempt is None or previous_attempt.state not in TERMINAL_ATTEMPT_STATES:
                raise InvalidStateTransition("human retry requires a terminal previous attempt")

            session.add(
                HumanReviewRecord(
                    task_id=task.id,
                    attempt_id=previous_attempt.id,
                    actor=review.actor,
                    decision=review.decision,
                    rationale=review.rationale,
                    github_reference=review.github_reference,
                )
            )
            retry_decision = RetryDecisionRecord(
                retry_id=retry_id,
                task_id=task.id,
                previous_attempt_id=previous_attempt.id,
                actor=review.actor,
                rationale=review.rationale,
                source="human_review_retry",
                decision_type=review.decision,
                github_reference=review.github_reference,
            )
            session.add(retry_decision)
            record_task_transition(
                session,
                task,
                TaskState.AWAITING_HUMAN_REVIEW,
                TaskState.READY,
                "human_review_retry",
                review.actor,
            )
            return self._task_view(session, task)

    def _task_view_for_request(
        self,
        session: Session,
        request_record: RequestRecord,
        duplicate: bool = False,
        duplicate_retry: bool = False,
        failure_reason: str | None = None,
    ) -> TaskView:
        task = session.scalar(
            select(TaskRecord)
            .where(TaskRecord.request_id == request_record.id)
            .order_by(TaskRecord.id.desc())
        )
        if task is None:
            raise TaskNotFound("task not found for request")
        return self._task_view(
            session,
            task,
            duplicate=duplicate,
            duplicate_retry=duplicate_retry,
            failure_reason=failure_reason,
        )

    def _task_view(
        self,
        session: Session,
        task: TaskRecord,
        duplicate: bool = False,
        duplicate_retry: bool = False,
        failure_reason: str | None = None,
    ) -> TaskView:
        request_record = session.get(RequestRecord, task.request_id)
        attempts = list(
            session.scalars(
                select(AttemptRecord)
                .where(AttemptRecord.task_id == task.id)
                .order_by(AttemptRecord.id)
            )
        )
        attempt = attempts[-1] if attempts else None
        attempt_ids = [item.id for item in attempts]
        transition_records = (
            list(
                session.scalars(
                    select(AttemptTransitionRecord)
                    .where(AttemptTransitionRecord.attempt_id.in_(attempt_ids))
                    .order_by(AttemptTransitionRecord.id)
                )
            )
            if attempt_ids
            else []
        )
        transitions_by_attempt: dict[int, list[TransitionView]] = {
            attempt_id: [] for attempt_id in attempt_ids
        }
        for transition in transition_records:
            transitions_by_attempt[transition.attempt_id].append(
                transition_view(transition)
            )

        results = list(
            session.scalars(
                select(InvestigationResultRecord)
                .where(InvestigationResultRecord.task_id == task.id)
                .order_by(InvestigationResultRecord.id)
            )
        )
        result = results[-1] if results else None
        attempt_id_by_record_id = {item.id: item.attempt_id for item in attempts}
        reviews = list(
            session.scalars(
                select(HumanReviewRecord)
                .where(HumanReviewRecord.task_id == task.id)
                .order_by(HumanReviewRecord.id)
            )
        )
        artifacts = list(
            session.scalars(
                select(EvidenceArtifactRecord)
                .join(AttemptRecord, EvidenceArtifactRecord.attempt_id == AttemptRecord.id)
                .where(AttemptRecord.task_id == task.id)
                .order_by(EvidenceArtifactRecord.id)
            )
        )
        publications = list(
            session.scalars(
                select(GitHubPublicationRecord)
                .where(GitHubPublicationRecord.task_id == task.id)
                .order_by(GitHubPublicationRecord.id)
            )
        )
        capability_checks = list(
            session.scalars(
                select(CapabilityCheckRecord)
                .where(CapabilityCheckRecord.attempt_id.in_(attempt_ids))
                .order_by(CapabilityCheckRecord.id)
            )
            if attempt_ids
            else []
        )
        invocations = list(
            session.scalars(
                select(ExecutorInvocationRecord)
                .where(ExecutorInvocationRecord.attempt_id.in_(attempt_ids))
                .order_by(ExecutorInvocationRecord.id)
            )
            if attempt_ids
            else []
        )
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
            duplicate_retry_submission=duplicate_retry,
            failure_reason=failure_reason,
            task_transitions=[
                TransitionView(
                    from_state=transition.from_state,
                    to_state=transition.to_state,
                    reason=transition.reason,
                    actor=transition.actor,
                    fencing_token=transition.fencing_token,
                )
                for transition in session.scalars(
                    select(TaskTransitionRecord)
                    .where(TaskTransitionRecord.task_id == task.id)
                    .order_by(TaskTransitionRecord.id)
                )
            ],
            attempt_transitions=(
                transitions_by_attempt.get(attempt.id, []) if attempt else []
            ),
            attempts=[
                AttemptHistoryView(
                    attempt_id=item.attempt_id,
                    state=item.state,
                    transitions=transitions_by_attempt[item.id],
                )
                for item in attempts
            ],
            results=[
                ResultHistoryView(
                    result_id=item.result_id,
                    attempt_id=attempt_id_by_record_id[item.attempt_id],
                    status=item.status,
                    executor_id=item.executor_id,
                )
                for item in results
            ],
            reviews=[
                HumanReviewView(
                    attempt_id=(
                        attempt_id_by_record_id.get(item.attempt_id)
                        if item.attempt_id is not None
                        else None
                    ),
                    actor=item.actor,
                    decision=item.decision,
                    rationale=item.rationale,
                    github_reference=item.github_reference,
                )
                for item in reviews
            ],
            evidence_artifacts=[
                EvidenceArtifactView(
                    attempt_id=attempt_id_by_record_id[item.attempt_id],
                    artifact_uri=item.artifact_uri,
                    sha256=item.sha256,
                    content_type=item.content_type,
                    sanitization_status=item.sanitization_status,
                    retention_policy=item.retention_policy,
                )
                for item in artifacts
            ],
            publications=[
                PublicationHistoryView(
                    attempt_id=(
                        attempt_id_by_record_id.get(item.attempt_id)
                        if item.attempt_id is not None
                        else None
                    ),
                    idempotency_key=item.idempotency_key,
                    attempt_sequence=item.attempt_sequence,
                    payload_sha256=item.payload_sha256,
                    status=item.status,
                    github_reference=item.github_reference,
                    error_category=item.error_category,
                )
                for item in publications
            ],
            capability_checks=[
                CapabilityCheckHistoryView(
                    attempt_id=(
                        attempt_id_by_record_id.get(item.attempt_id)
                        if item.attempt_id is not None
                        else None
                    ),
                    executor_id=item.executor_id,
                    status=item.status,
                )
                for item in capability_checks
            ],
            executor_invocations=[
                ExecutorInvocationHistoryView(
                    attempt_id=attempt_id_by_record_id[item.attempt_id],
                    executor_id=item.executor_id,
                    operation=item.operation,
                    idempotency_key=item.idempotency_key,
                    fencing_token=item.fencing_token,
                    status=item.status,
                    error_category=item.error_category,
                )
                for item in invocations
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


def transition_view(
    transition: TaskTransitionRecord | AttemptTransitionRecord,
) -> TransitionView:
    return TransitionView(
        from_state=transition.from_state,
        to_state=transition.to_state,
        reason=transition.reason,
        actor=transition.actor,
        fencing_token=transition.fencing_token,
    )


def find_request_by_fingerprint(session: Session, fingerprint: str) -> RequestRecord | None:
    for request_record in session.scalars(select(RequestRecord).order_by(RequestRecord.id)):
        if request_record.payload.get("signal", {}).get("fingerprint") == fingerprint:
            return request_record
    return None


def find_retry_decision(session: Session, retry_id: str) -> RetryDecisionRecord | None:
    return session.scalar(
        select(RetryDecisionRecord).where(RetryDecisionRecord.retry_id == retry_id)
    )


def assert_retry_decision_matches(
    existing: RetryDecisionRecord,
    *,
    task_id: int,
    actor: str,
    rationale: str,
    source: str,
    decision_type: str,
    github_reference: str | None,
) -> None:
    expected = (
        task_id,
        actor,
        rationale,
        source,
        str(decision_type),
        github_reference,
    )
    actual = (
        existing.task_id,
        existing.actor,
        existing.rationale,
        existing.source,
        existing.decision_type,
        existing.github_reference,
    )
    if actual != expected:
        raise DuplicateRetryConflict(
            "retry_id already exists with a different decision payload"
        )


def assert_task_can_retry(task: TaskRecord) -> None:
    if task.state in TERMINAL_TASK_STATES:
        raise InvalidStateTransition("terminal tasks cannot create retry attempts")
    if task.state != TaskState.READY:
        raise InvalidStateTransition("operator retry is allowed only from READY")


def ensure_no_active_attempt(session: Session) -> None:
    active_attempt = session.scalar(
        select(AttemptRecord).where(AttemptRecord.state.in_(ACTIVE_ATTEMPT_STATES))
    )
    if active_attempt is not None:
        raise InvalidStateTransition("retry is blocked while an attempt is active")


def ensure_no_pending_retry_decision(session: Session, task: TaskRecord) -> None:
    if pending_retry_decision(session, task) is not None:
        raise InvalidStateTransition("task already has a pending retry decision")


def pending_retry_decision(session: Session, task: TaskRecord) -> RetryDecisionRecord | None:
    return session.scalar(
        select(RetryDecisionRecord)
        .where(
            RetryDecisionRecord.task_id == task.id,
            RetryDecisionRecord.new_attempt_id.is_(None),
        )
        .order_by(RetryDecisionRecord.id.desc())
    )


def utc_now() -> datetime:
    return datetime.now(UTC)


def as_utc(timestamp: datetime) -> datetime:
    if timestamp.tzinfo is None:
        return timestamp.replace(tzinfo=UTC)
    return timestamp.astimezone(UTC)


def lock_dispatch_lease(session: Session, now: datetime) -> DispatchLeaseRecord:
    lease = session.scalar(
        select(DispatchLeaseRecord)
        .where(DispatchLeaseRecord.lease_name == DISPATCH_LEASE_NAME)
        .with_for_update()
    )
    if lease is None:
        lease = DispatchLeaseRecord(
            lease_name=DISPATCH_LEASE_NAME,
            lease_owner="unclaimed",
            expires_at=now,
            heartbeat_at=now,
            fencing_token=0,
        )
        session.add(lease)
        session.flush()
    return lease


def lease_is_active(lease: DispatchLeaseRecord, now: datetime) -> bool:
    return lease.task_id is not None and as_utc(lease.expires_at) > now


def claim_dispatch_lease(
    lease: DispatchLeaseRecord,
    lease_owner: str,
    task_id: int,
    now: datetime,
) -> None:
    lease.lease_owner = lease_owner
    lease.expires_at = now + DISPATCH_LEASE_DURATION
    lease.heartbeat_at = now
    lease.fencing_token += 1
    lease.task_id = task_id
    lease.attempt_id = None


def claim_reconciliation_lease(
    lease: DispatchLeaseRecord,
    lease_owner: str,
    task_id: int,
    attempt: AttemptRecord,
    now: datetime,
) -> None:
    lease.lease_owner = lease_owner
    lease.expires_at = now + DISPATCH_LEASE_DURATION
    lease.heartbeat_at = now
    lease.fencing_token += 1
    lease.task_id = task_id
    lease.attempt_id = attempt.id
    attempt.fencing_token = lease.fencing_token


def release_dispatch_lease(lease: DispatchLeaseRecord, now: datetime) -> None:
    lease.expires_at = now
    lease.heartbeat_at = now
    lease.task_id = None
    lease.attempt_id = None


def renew_dispatch_lease(lease: DispatchLeaseRecord, now: datetime) -> None:
    lease.expires_at = now + DISPATCH_LEASE_DURATION
    lease.heartbeat_at = now


def lease_task_id(session: Session, lease: DispatchLeaseRecord) -> str | None:
    if lease.task_id is None:
        return None
    task = session.get(TaskRecord, lease.task_id)
    return task.task_id if task is not None else None


def lease_attempt_id(session: Session, lease: DispatchLeaseRecord) -> str | None:
    if lease.attempt_id is None:
        return None
    attempt = session.get(AttemptRecord, lease.attempt_id)
    return attempt.attempt_id if attempt is not None else None


def assert_current_dispatch_lease(
    session: Session,
    task: TaskRecord,
    attempt: AttemptRecord,
    lease_owner: str,
    fencing_token: int,
) -> DispatchLeaseRecord:
    lease = session.scalar(
        select(DispatchLeaseRecord)
        .where(DispatchLeaseRecord.lease_name == DISPATCH_LEASE_NAME)
        .with_for_update()
    )
    if (
        lease is None
        or lease.lease_owner != lease_owner
        or lease.fencing_token != fencing_token
        or lease.task_id != task.id
        or lease.attempt_id != attempt.id
        or attempt.fencing_token != fencing_token
    ):
        log_lifecycle(
            "stale_fencing_token_ignored",
            task_id=task.task_id,
            attempt_id=attempt.attempt_id,
            fencing_token=str(fencing_token),
        )
        raise StaleFencingToken("attempt outcome has an obsolete fencing token")
    return lease


def result_identity_failure(
    result,
    task_id: str,
    attempt_id: str,
    executor_id: str,
) -> str | None:
    if result.task_id != task_id:
        return "result_malformed:task_id_mismatch"
    if result.attempt_id != attempt_id:
        return "result_malformed:attempt_id_mismatch"
    if result.executor_id != executor_id:
        return "result_malformed:executor_id_mismatch"
    return None


def attempt_status_identity_failure(
    status,
    attempt_id: str,
    executor_id: str,
) -> str | None:
    if status.attempt_id != attempt_id:
        return "reconciliation_status_attempt_id_mismatch"
    if status.executor_id != executor_id:
        return "reconciliation_status_executor_id_mismatch"
    return None


def validate_attempt_status(raw_status) -> "AttemptStatus":
    from sre_control_plane.executor import AttemptStatus

    return AttemptStatus.model_validate(model_payload(raw_status))


def validate_investigation_result(raw_result) -> InvestigationResult:
    return InvestigationResult.model_validate(model_payload(raw_result))


def model_payload(value):
    if hasattr(value, "model_dump"):
        return value.model_dump(mode="json")
    return value


def advance_attempt_to_running(
    session: Session,
    attempt: AttemptRecord,
    reason: str,
) -> None:
    if attempt.state == AttemptState.CAPABILITY_CHECKED:
        record_attempt_transition(
            session,
            attempt,
            AttemptState.CAPABILITY_CHECKED,
            AttemptState.DISPATCHED,
            reason,
            "control-plane",
        )
    if attempt.state == AttemptState.DISPATCHED:
        record_attempt_transition(
            session,
            attempt,
            AttemptState.DISPATCHED,
            AttemptState.RUNNING,
            reason,
            "control-plane",
        )
    if attempt.state != AttemptState.RUNNING:
        raise InvalidStateTransition(
            f"reconciliation cannot confirm an active executor state from {attempt.state}"
        )


def update_invocation_status(
    session: Session,
    attempt: AttemptRecord,
    status: str,
    error_category: str | None = None,
) -> None:
    invocation = session.scalar(
        select(ExecutorInvocationRecord)
        .where(ExecutorInvocationRecord.attempt_id == attempt.id)
        .order_by(ExecutorInvocationRecord.id.desc())
    )
    if invocation is not None:
        invocation.status = str(status)
        invocation.error_category = error_category


def record_task_transition(
    session: Session,
    task: TaskRecord,
    from_state: str | None,
    to_state: str,
    reason: str,
    actor: str,
    fencing_token: int | None = None,
) -> None:
    assert_transition_allowed(ALLOWED_TASK_TRANSITIONS, from_state, to_state)
    assert_record_state(task.state, from_state)
    task.state = to_state
    session.add(
        TaskTransitionRecord(
            task_id=task.id,
            from_state=from_state,
            to_state=to_state,
            reason=reason,
            actor=actor,
            fencing_token=fencing_token,
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
    assert_record_state(attempt.state, from_state)
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


def assert_record_state(current_state: str, expected_state: str | None) -> None:
    if expected_state is not None and current_state != expected_state:
        raise InvalidStateTransition(
            f"record is in {current_state}; expected {expected_state}"
        )


def latest_attempt(session: Session, task: TaskRecord) -> AttemptRecord | None:
    return session.scalar(
        select(AttemptRecord)
        .where(AttemptRecord.task_id == task.id)
        .order_by(AttemptRecord.id.desc())
    )


def count_attempts(session: Session, task: TaskRecord) -> int:
    return len(
        list(
            session.scalars(
                select(AttemptRecord.id).where(AttemptRecord.task_id == task.id)
            )
        )
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


def timeline_payload(session: Session, model, foreign_key: str, record_id: int) -> list[dict]:
    column = getattr(model, foreign_key)
    return [
        {
            "from_state": item.from_state,
            "to_state": item.to_state,
            "reason": item.reason,
            "actor": item.actor,
            "fencing_token": item.fencing_token,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
        for item in session.scalars(select(model).where(column == record_id).order_by(model.id))
    ]


def capability_payload(session: Session, attempt_id: int) -> list[dict]:
    return [
        {
            "executor_id": item.executor_id,
            "status": item.status,
            "declared_capabilities": item.declared_capabilities,
            "denied_capabilities": item.denied_capabilities,
            "target_scope": item.target_scope,
            "verification_evidence": item.verification_evidence,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
        for item in session.scalars(
            select(CapabilityCheckRecord)
            .where(CapabilityCheckRecord.attempt_id == attempt_id)
            .order_by(CapabilityCheckRecord.id)
        )
    ]


def invocation_payload(session: Session, attempt_id: int) -> list[dict]:
    return [
        {
            "executor_id": item.executor_id,
            "operation": item.operation,
            "idempotency_key": item.idempotency_key,
            "fencing_token": item.fencing_token,
            "status": item.status,
            "error_category": item.error_category,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        }
        for item in session.scalars(
            select(ExecutorInvocationRecord)
            .where(ExecutorInvocationRecord.attempt_id == attempt_id)
            .order_by(ExecutorInvocationRecord.id)
        )
    ]


def publication_payload_for_result(result_payload: dict, artifact_uri: str) -> dict:
    result = InvestigationResult.model_validate(result_payload)
    return {
        "status": result.status,
        "summary": result.summary,
        "findings": [
            {
                "finding_id": finding.finding_id,
                "statement": finding.statement,
                "evidence_ids": finding.evidence_ids,
                "limitations": finding.limitations,
            }
            for finding in result.findings
        ],
        "evidence_references": [artifact_uri],
        "limitations": result.limitations,
        "human_review": "Explicit human review and closeout are required.",
    }


def stable_id(prefix: Literal["task"], value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]
    return f"{prefix}-{digest}"


def log_lifecycle(event: str, **fields: str | None) -> None:
    LOGGER.info(json.dumps({"event": event, **fields}, sort_keys=True))
