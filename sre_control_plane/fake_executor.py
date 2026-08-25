from __future__ import annotations

from copy import deepcopy

from sre_control_plane.contracts import (
    MVP_GITOPS_APPLICATION,
    MVP_NAMESPACE,
    MVP_ROLLOUT,
    MVP_WORKLOAD,
    REQUIRED_CAPABILITIES,
    InvestigationResult,
)
from sre_control_plane.executor import (
    AttemptStatus,
    CancelAttemptResponse,
    CapabilityReport,
    ExecutorStatus,
    StartInvestigationCommand,
    StartInvestigationResponse,
)


class FakeInvestigationExecutor:
    """Deterministic local executor for contract and lifecycle tests only."""

    executor_id = "executor-fake-readonly-sre-001"

    def __init__(self) -> None:
        self._started: dict[str, StartInvestigationResponse] = {}
        self._commands: dict[str, StartInvestigationCommand] = {}

    def describe_capabilities(self) -> CapabilityReport:
        return CapabilityReport(
            executor_id=self.executor_id,
            schema_versions=["1.0"],
            declared_capabilities=sorted(REQUIRED_CAPABILITIES),
            denied_capabilities=[
                "kubernetes.write",
                "rollout.mutate",
                "gitops.write",
                "deployment.write",
                "remediation.execute",
                "pull_request.merge",
                "incident.close",
                "secrets.read",
            ],
            target_scope={
                "namespace": MVP_NAMESPACE,
                "workload": MVP_WORKLOAD,
                "rollout": MVP_ROLLOUT,
                "gitops_application": MVP_GITOPS_APPLICATION,
            },
            auth_mode="fake-local-no-credentials",
            verification_evidence=[
                "No external system access is available in the fake executor.",
                "Capabilities are deterministic test declarations only.",
            ],
            supports_idempotent_start=True,
            supports_status_lookup=True,
        )

    def start_investigation(self, command: StartInvestigationCommand) -> StartInvestigationResponse:
        existing = self._started.get(command.idempotency_key)
        if existing is not None:
            return existing

        response = StartInvestigationResponse(
            executor_id=self.executor_id,
            attempt_id=command.attempt_id,
            status=ExecutorStatus.SUCCEEDED,
            idempotency_key=command.idempotency_key,
            fencing_token=command.fencing_token,
        )
        self._started[command.idempotency_key] = response
        self._commands[command.idempotency_key] = command
        return response

    def get_status(self, attempt_id: str, idempotency_key: str) -> AttemptStatus:
        response = self._started.get(idempotency_key)
        if response is None or response.attempt_id != attempt_id:
            return AttemptStatus(
                executor_id=self.executor_id,
                attempt_id=attempt_id,
                status=ExecutorStatus.STALE,
            )
        return AttemptStatus(
            executor_id=self.executor_id,
            attempt_id=attempt_id,
            status=response.status,
        )

    def get_result(self, attempt_id: str, idempotency_key: str) -> InvestigationResult:
        command = self._commands[idempotency_key]
        result = deepcopy(CANONICAL_FAKE_RESULT)
        result["result_id"] = f"result-{attempt_id}"
        result["task_id"] = command.task_id
        result["attempt_id"] = attempt_id
        result["executor_id"] = self.executor_id
        return InvestigationResult.model_validate(result)

    def cancel_attempt(self, attempt_id: str, idempotency_key: str) -> CancelAttemptResponse:
        return CancelAttemptResponse(
            executor_id=self.executor_id,
            attempt_id=attempt_id,
            status=ExecutorStatus.CANCELLED,
            partial_evidence_available=False,
        )


CANONICAL_FAKE_RESULT = {
    "schema_version": "1.0",
    "result_id": "result-20260813-stage-001",
    "task_id": "task-20260813-stage-001",
    "attempt_id": "attempt-20260813-stage-001-a1",
    "executor_id": "executor-fake-readonly-sre-001",
    "status": "succeeded",
    "summary": (
        "Controlled stage failure traffic is associated with elevated frontend "
        "SLO error signals during the approved time range."
    ),
    "findings": [
        {
            "finding_id": "finding-001",
            "severity": "high",
            "confidence": "medium",
            "classification": "inference",
            "statement": (
                "The elevated error ratio is probably associated with requests "
                "to the approved stage failure path."
            ),
            "evidence_ids": ["evidence-prom-er5", "evidence-ingress-logs"],
            "limitations": [
                "Failure traffic source was identified by request scope, not started by the AI Operations Platform."
            ],
        }
    ],
    "probable_causes": [
        {
            "cause_id": "cause-001",
            "confidence": "medium",
            "statement": "Controlled failure endpoint traffic is the likely cause of the SLO burn-rate increase.",
            "evidence_ids": ["evidence-prom-br5", "evidence-request"],
        }
    ],
    "evidence": [
        {
            "evidence_id": "evidence-prom-br5",
            "type": "prometheus_query",
            "source": "sre_platform_observed",
            "reference": "github-issue-comment-or-artifact-reference",
            "supports": ["finding-001", "cause-001"],
            "does_not_prove": "It does not prove recovery or production behavior.",
        },
        {
            "evidence_id": "evidence-prom-er5",
            "type": "prometheus_query",
            "source": "sre_platform_observed",
            "reference": "github-issue-comment-or-artifact-reference",
            "supports": ["finding-001"],
            "does_not_prove": "It does not prove recovery or production behavior.",
        },
        {
            "evidence_id": "evidence-ingress-logs",
            "type": "logs",
            "source": "sre_platform_observed",
            "reference": "github-issue-comment-or-artifact-reference",
            "supports": ["finding-001"],
            "does_not_prove": "It does not prove root cause without SLO evidence.",
        },
        {
            "evidence_id": "evidence-request",
            "type": "operator_request",
            "source": "operator_provided",
            "reference": "github-issue-comment-or-artifact-reference",
            "supports": ["cause-001"],
            "does_not_prove": "It does not prove runtime behavior.",
        },
    ],
    "limitations": ["Recovery was not checked during this attempt."],
    "recommendations": [
        {
            "recommendation_id": "rec-001",
            "type": "operator_action",
            "statement": (
                "Review SRE Platform rollout and stop the controlled failure "
                "source according to the SRE-owned procedure."
            ),
            "requires_human_action": True,
            "executes_remediation": False,
        }
    ],
    "recovery_status": "not_checked",
    "human_review": {
        "required": True,
        "status": "pending",
        "reference": None,
    },
    "github_references": [
        {
            "type": "issue_comment",
            "url": "https://github.com/DimitryZH/ai-operations-platform/issues/21#issuecomment-placeholder",
        }
    ],
}
