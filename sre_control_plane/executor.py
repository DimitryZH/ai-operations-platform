from __future__ import annotations

from enum import StrEnum
from typing import Literal, Protocol

from pydantic import BaseModel, ConfigDict, Field

from sre_control_plane.contracts import InvestigationRequest, InvestigationResult


class ExecutorStatus(StrEnum):
    ACCEPTED = "accepted"
    QUEUED = "queued"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    DISPATCH_FAILED = "dispatch_failed"
    FAILED = "failed"
    TIMED_OUT = "timed_out"
    STALE = "stale"
    CANCELLED = "cancelled"


class AdapterModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CapabilityReport(AdapterModel):
    executor_id: str
    schema_versions: list[str]
    declared_capabilities: list[str]
    denied_capabilities: list[str]
    target_scope: dict[str, str]
    auth_mode: str
    verification_evidence: list[str]
    supports_idempotent_start: bool
    supports_status_lookup: bool
    idempotency_scope: Literal["durable", "process_local"]


class StartInvestigationCommand(AdapterModel):
    request: InvestigationRequest
    task_id: str
    attempt_id: str
    idempotency_key: str
    fencing_token: int = Field(ge=1)


class StartInvestigationResponse(AdapterModel):
    executor_id: str
    attempt_id: str
    status: ExecutorStatus
    idempotency_key: str
    fencing_token: int


class AttemptStatus(AdapterModel):
    executor_id: str
    attempt_id: str
    status: ExecutorStatus


class CancelAttemptResponse(AdapterModel):
    executor_id: str
    attempt_id: str
    status: ExecutorStatus
    partial_evidence_available: bool


class InvestigationExecutor(Protocol):
    def describe_capabilities(self) -> CapabilityReport:
        """Return a fail-closed capability declaration for the approved scope."""

    def start_investigation(self, command: StartInvestigationCommand) -> StartInvestigationResponse:
        """Start or return the same bounded attempt for the idempotency key."""

    def get_status(self, attempt_id: str, idempotency_key: str) -> AttemptStatus:
        """Read attempt status by durable attempt identity without mutating control-plane state."""

    def get_result(self, attempt_id: str, idempotency_key: str) -> InvestigationResult:
        """Return a schema-valid normalized result for a completed fake attempt."""

    def cancel_attempt(self, attempt_id: str, idempotency_key: str) -> CancelAttemptResponse:
        """Request bounded cancellation without executing remediation."""
