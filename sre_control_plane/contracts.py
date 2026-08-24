from __future__ import annotations

import re
from datetime import datetime, timedelta
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

SCHEMA_VERSION = "1.0"
MVP_SOURCE_SYSTEM = "sre-platform"
MVP_ENVIRONMENT = "staging"
MVP_SERVICE = "frontend"
MVP_NAMESPACE = "online-shop-stage"
MVP_WORKLOAD = "frontend"
MVP_ROLLOUT = "frontend"
MVP_GITOPS_APPLICATION = "online-shop-stage"
MAX_TIME_RANGE = timedelta(minutes=60)

REQUIRED_CAPABILITIES = frozenset(
    {
        "kubernetes.read",
        "prometheus.query",
        "rollout.read",
        "gitops.read",
        "logs.read",
        "investigation.report",
    }
)

UNSAFE_TEXT_PATTERNS = (
    re.compile(r"(?i)(api[_-]?key|token|secret|password)\s*[:=]"),
    re.compile(r"(?i)\b(bearer|basic)\s+[a-z0-9._~+/-]+=*"),
    re.compile(
        r"\b(localhost|127\.0\.0\.1|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|"
        r"192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})\b"
    ),
    re.compile(r"[A-Za-z]:\\"),
)


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SourceType(StrEnum):
    OPERATOR = "operator"
    SRE_EVENT = "sre_event"


class SignalStatus(StrEnum):
    FIRING = "firing"
    RESOLVED = "resolved"
    MANUAL = "manual"


class ResultStatus(StrEnum):
    SUCCEEDED = "succeeded"
    PARTIAL = "partial"
    FAILED = "failed"


class Severity(StrEnum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFORMATIONAL = "informational"


class Confidence(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    UNKNOWN = "unknown"


class EvidenceClassification(StrEnum):
    SRE_PLATFORM_OBSERVED = "sre_platform_observed"
    OPERATOR_PROVIDED = "operator_provided"
    AI_INTERPRETATION = "ai_interpretation"
    INFERENCE = "inference"
    UNAVAILABLE = "unavailable"


class RecoveryStatus(StrEnum):
    NOT_CHECKED = "not_checked"
    STILL_FAILING = "still_failing"
    RECOVERED = "recovered"
    UNKNOWN = "unknown"


class InvestigationSource(StrictModel):
    type: SourceType
    system: Literal["sre-platform"]
    reference: str | None = None


class InvestigationScenario(StrictModel):
    type: Literal["slo_investigation"]
    environment: Literal["staging"]
    service: Literal["frontend"]
    summary: str = Field(min_length=1, max_length=1000)


class InvestigationTimeRange(StrictModel):
    start: datetime
    end: datetime

    @model_validator(mode="after")
    def validate_bounds(self) -> "InvestigationTimeRange":
        if self.end <= self.start:
            raise ValueError("scope.time_range.end must be later than start")
        if self.end - self.start > MAX_TIME_RANGE:
            raise ValueError("scope.time_range must not exceed 60 minutes")
        return self


class InvestigationScope(StrictModel):
    cluster: str = Field(min_length=1, max_length=128)
    namespace: Literal["online-shop-stage"]
    workload: Literal["frontend"]
    rollout: Literal["frontend"]
    gitops_application: Literal["online-shop-stage"]
    time_range: InvestigationTimeRange


class SignalReference(StrictModel):
    type: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=128)


class InvestigationSignal(StrictModel):
    status: SignalStatus
    name: str = Field(min_length=1, max_length=128)
    fingerprint: str = Field(min_length=1, max_length=256)
    observed_at: datetime
    references: list[SignalReference] = Field(default_factory=list)


class InvestigationConstraints(StrictModel):
    read_only: Literal[True]
    allow_mutation: Literal[False]
    require_human_closeout: Literal[True]


class InvestigationRequest(StrictModel):
    schema_version: Literal["1.0"]
    request_id: str = Field(min_length=1, max_length=128)
    source: InvestigationSource
    scenario: InvestigationScenario
    scope: InvestigationScope
    signal: InvestigationSignal
    requested_capabilities: list[str] = Field(min_length=1)
    constraints: InvestigationConstraints

    @field_validator("requested_capabilities")
    @classmethod
    def validate_capabilities(cls, capabilities: list[str]) -> list[str]:
        if len(capabilities) != len(set(capabilities)):
            raise ValueError("requested_capabilities must not contain duplicates")
        if set(capabilities) != REQUIRED_CAPABILITIES:
            raise ValueError("requested_capabilities must match the accepted MVP capability set")
        return capabilities

    @model_validator(mode="after")
    def validate_signal_window_and_safety(self) -> "InvestigationRequest":
        allowed_skew = timedelta(minutes=5)
        if self.signal.observed_at < self.scope.time_range.start - allowed_skew:
            raise ValueError("signal.observed_at is outside the approved time range")
        if self.signal.observed_at > self.scope.time_range.end + allowed_skew:
            raise ValueError("signal.observed_at is outside the approved time range")
        unsafe_value = first_unsafe_string(self.model_dump(mode="json"))
        if unsafe_value is not None:
            raise ValueError("request contains unsafe secret, private endpoint, or machine-local path")
        return self


class Finding(StrictModel):
    finding_id: str = Field(min_length=1, max_length=128)
    severity: Severity
    confidence: Confidence
    classification: EvidenceClassification
    statement: str = Field(min_length=1, max_length=2000)
    evidence_ids: list[str] = Field(min_length=1)
    limitations: list[str] = Field(default_factory=list)


class ProbableCause(StrictModel):
    cause_id: str = Field(min_length=1, max_length=128)
    confidence: Confidence
    statement: str = Field(min_length=1, max_length=2000)
    evidence_ids: list[str] = Field(min_length=1)


class EvidenceRecord(StrictModel):
    evidence_id: str = Field(min_length=1, max_length=128)
    type: str = Field(min_length=1, max_length=64)
    source: EvidenceClassification
    reference: str = Field(min_length=1, max_length=512)
    supports: list[str] = Field(default_factory=list)
    does_not_prove: str = Field(min_length=1, max_length=1000)


class Recommendation(StrictModel):
    recommendation_id: str = Field(min_length=1, max_length=128)
    type: str = Field(min_length=1, max_length=64)
    statement: str = Field(min_length=1, max_length=2000)
    requires_human_action: bool
    executes_remediation: Literal[False]


class HumanReview(StrictModel):
    required: Literal[True]
    status: Literal["pending", "accepted", "rejected", "cancelled"]
    reference: str | None = None


class GitHubReference(StrictModel):
    type: str = Field(min_length=1, max_length=64)
    url: str = Field(min_length=1, max_length=512)


class InvestigationResult(StrictModel):
    schema_version: Literal["1.0"]
    result_id: str = Field(min_length=1, max_length=128)
    task_id: str = Field(min_length=1, max_length=128)
    attempt_id: str = Field(min_length=1, max_length=128)
    executor_id: str = Field(min_length=1, max_length=128)
    status: ResultStatus
    summary: str = Field(min_length=1, max_length=2000)
    findings: list[Finding]
    probable_causes: list[ProbableCause]
    evidence: list[EvidenceRecord]
    limitations: list[str]
    recommendations: list[Recommendation]
    recovery_status: RecoveryStatus
    human_review: HumanReview
    github_references: list[GitHubReference]

    @model_validator(mode="after")
    def validate_result_integrity(self) -> "InvestigationResult":
        evidence_ids = {record.evidence_id for record in self.evidence}
        missing = sorted(
            evidence_id
            for item in [*self.findings, *self.probable_causes]
            for evidence_id in item.evidence_ids
            if evidence_id not in evidence_ids
        )
        if missing:
            raise ValueError(f"result references missing evidence IDs: {', '.join(missing)}")
        if self.status == ResultStatus.SUCCEEDED and not self.findings:
            raise ValueError("succeeded results require at least one finding")
        if self.status in {ResultStatus.PARTIAL, ResultStatus.FAILED} and not self.limitations:
            raise ValueError("partial or failed results require explicit limitations")
        return self


def first_unsafe_string(value: Any) -> str | None:
    for item in iter_strings(value):
        if any(pattern.search(item) for pattern in UNSAFE_TEXT_PATTERNS):
            return item
    return None


def iter_strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from iter_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_strings(child)
