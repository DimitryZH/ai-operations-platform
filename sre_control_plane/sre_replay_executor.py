from __future__ import annotations

import hashlib
import json
from copy import deepcopy
from dataclasses import dataclass, field
from threading import Lock
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

from sre_control_plane.contracts import (
    MVP_GITOPS_APPLICATION,
    MVP_NAMESPACE,
    MVP_ROLLOUT,
    MVP_WORKLOAD,
    REQUIRED_CAPABILITIES,
    InvestigationResult,
    first_unsafe_string,
)
from sre_control_plane.executor import (
    AttemptStatus,
    CancelAttemptResponse,
    CapabilityReport,
    ExecutorStatus,
    StartInvestigationCommand,
    StartInvestigationResponse,
)

SRE_REPLAY_EXECUTOR_ID = "executor-sre-replay-readonly-001"
SRE_REPLAY_SCENARIO_ID = "approved-stage-frontend-slo-v1"
SRE_REPLAY_AUTH_MODE = "sanitized-replay-fixture-no-credentials"

_APPROVED_CLUSTER = "sre-platform-staging"
_APPROVED_PROMETHEUS_QUERIES = frozenset(
    {
        "slo:burn_rate_5m",
        "slo:error_ratio_5m",
        'sum(rate(nginx_ingress_controller_requests{exported_namespace="online-shop-stage",status!=""}[5m]))',
    }
)
_APPROVED_KUBERNETES_RESOURCES = frozenset(
    {
        "analysisruns.argoproj.io",
        "events",
        "ingresses.networking.k8s.io",
        "pods",
        "rollouts.argoproj.io",
        "services",
    }
)
_APPROVED_GITOPS_PATHS = frozenset(
    {
        "charts/platform/templates/break-ingress.yaml",
        "charts/platform/templates/frontend-ingress.yaml",
        "charts/platform/templates/frontend-rollout.yaml",
        "charts/platform/templates/frontend-slo-check-analysis-template.yaml",
        "environments/stage/argocd/apps/online-shop-stage.yaml",
        "environments/stage/values/platform.yaml",
    }
)
_READ_ONLY_VERBS = frozenset({"get", "list"})
_READ_ONLY_GITOPS_ACTIONS = frozenset({"read_file"})
_READ_ONLY_RECOVERY_ACTIONS = frozenset({"observe_status"})
_MUTATION_DENIALS = frozenset(
    {
        "kubernetes.write",
        "rollout.mutate",
        "gitops.write",
        "deployment.write",
        "remediation.execute",
        "pull_request.merge",
        "incident.close",
        "secrets.read",
    }
)
_WRITE_HINTS = (
    "apply",
    "approve",
    "abort",
    "close",
    "create",
    "delete",
    "edit",
    "execute",
    "merge",
    "patch",
    "promote",
    "restart",
    "retry",
    "rollback",
    "scale",
    "sync",
    "update",
    "write",
)


class SreReplayExecutorError(RuntimeError):
    """Controlled replay adapter error that omits provider details."""


class SreReplayRejected(SreReplayExecutorError):
    pass


class _StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class KubernetesReplayProviderDeclaration(_StrictModel):
    provider: Literal["kubernetes"]
    mode: Literal["sanitized_replay"]
    cluster: Literal["sre-platform-staging"]
    namespaces: list[Literal["online-shop-stage"]] = Field(min_length=1, max_length=1)
    resources: list[str] = Field(min_length=1, max_length=12)
    verbs: list[str] = Field(min_length=1, max_length=4)


class PrometheusReplayProviderDeclaration(_StrictModel):
    provider: Literal["prometheus"]
    mode: Literal["sanitized_replay"]
    query_names: list[str] = Field(min_length=1, max_length=4)
    query_allowlist: list[str] = Field(min_length=1, max_length=8)


class GitOpsReplayProviderDeclaration(_StrictModel):
    provider: Literal["gitops"]
    mode: Literal["sanitized_replay"]
    repository: Literal["DimitryZH/sre-platform"]
    ref: Literal["main"]
    paths: list[str] = Field(min_length=1, max_length=12)
    actions: list[str] = Field(min_length=1, max_length=4)


class RecoveryObservationReplayProviderDeclaration(_StrictModel):
    provider: Literal["recovery_observation"]
    mode: Literal["sanitized_replay"]
    optional: Literal[True]
    actions: list[str] = Field(min_length=1, max_length=2)
    claims_live_recovery: Literal[False]


class SreReplayProviderDeclarations(_StrictModel):
    scenario_id: Literal["approved-stage-frontend-slo-v1"]
    kubernetes: KubernetesReplayProviderDeclaration
    prometheus: PrometheusReplayProviderDeclaration
    gitops: GitOpsReplayProviderDeclaration
    recovery_observation: RecoveryObservationReplayProviderDeclaration | None = None

    @model_validator(mode="after")
    def validate_approved_read_only_contract(self) -> "SreReplayProviderDeclarations":
        failure = replay_declaration_failure(self)
        if failure is not None:
            raise ValueError("SRE replay provider declaration is outside the approved read-only scope")
        return self


@dataclass(frozen=True)
class SreReplayExecutorConfig:
    scenario_id: str
    provider_declarations: SreReplayProviderDeclarations = field(repr=False)

    def __post_init__(self) -> None:
        if self.scenario_id != SRE_REPLAY_SCENARIO_ID:
            raise ValueError("SRE replay executor configuration is invalid")
        failure = replay_declaration_failure(self.provider_declarations)
        if failure is not None:
            raise ValueError("SRE replay executor configuration is invalid")


class SreReplayExecutor:
    """Bounded SRE investigation adapter backed only by sanitized replay fixtures."""

    executor_id = SRE_REPLAY_EXECUTOR_ID

    def __init__(self, config: SreReplayExecutorConfig) -> None:
        self._config = config
        self._lock = Lock()
        self._started: dict[str, tuple[str, StartInvestigationResponse]] = {}
        self._results: dict[str, InvestigationResult] = {}

    def describe_capabilities(self) -> CapabilityReport:
        failure = replay_declaration_failure(self._config.provider_declarations)
        if failure is not None:
            raise SreReplayRejected("SRE replay capability declaration is not approved")
        return CapabilityReport(
            executor_id=self.executor_id,
            schema_versions=["1.0"],
            declared_capabilities=sorted(REQUIRED_CAPABILITIES),
            denied_capabilities=sorted(_MUTATION_DENIALS),
            target_scope={
                "namespace": MVP_NAMESPACE,
                "workload": MVP_WORKLOAD,
                "rollout": MVP_ROLLOUT,
                "gitops_application": MVP_GITOPS_APPLICATION,
            },
            auth_mode=SRE_REPLAY_AUTH_MODE,
            verification_evidence=[
                f"Approved scenario: {self._config.scenario_id}; logical cluster: {_APPROVED_CLUSTER}.",
                "Provider declarations match the approved staging read-only replay contract.",
                "Prometheus queries are restricted to the approved allowlist.",
                "Kubernetes, GitOps, and recovery provider actions are read-only.",
                "Replay fixture validation only; no live staging or production validation.",
            ],
            supports_idempotent_start=True,
            supports_status_lookup=True,
            idempotency_scope="durable",
        )

    def start_investigation(self, command: StartInvestigationCommand) -> StartInvestigationResponse:
        validate_replay_command(command)
        semantic_identity = _command_semantic_identity(command)
        with self._lock:
            existing = self._started.get(command.idempotency_key)
            if existing is not None:
                existing_identity, existing_response = existing
                if existing_identity != semantic_identity:
                    raise SreReplayRejected("SRE replay idempotency identity conflicts")
                return existing_response

        result = build_replay_result(command, self._config.provider_declarations)
        response = StartInvestigationResponse(
            executor_id=self.executor_id,
            attempt_id=command.attempt_id,
            status=ExecutorStatus.SUCCEEDED,
            idempotency_key=command.idempotency_key,
            fencing_token=command.fencing_token,
        )
        with self._lock:
            self._started[command.idempotency_key] = (semantic_identity, response)
            self._results[command.idempotency_key] = result
        return response

    def get_status(self, attempt_id: str, idempotency_key: str) -> AttemptStatus:
        with self._lock:
            existing = self._started.get(idempotency_key)
        if existing is None or existing[1].attempt_id != attempt_id:
            return AttemptStatus(executor_id=self.executor_id, attempt_id=attempt_id, status=ExecutorStatus.STALE)
        return AttemptStatus(executor_id=self.executor_id, attempt_id=attempt_id, status=ExecutorStatus.SUCCEEDED)

    def get_result(self, attempt_id: str, idempotency_key: str) -> InvestigationResult:
        with self._lock:
            result = self._results.get(idempotency_key)
        if result is None or result.attempt_id != attempt_id:
            raise SreReplayRejected("SRE replay result identity is unavailable")
        return result

    def cancel_attempt(self, attempt_id: str, idempotency_key: str) -> CancelAttemptResponse:
        return CancelAttemptResponse(
            executor_id=self.executor_id,
            attempt_id=attempt_id,
            status=ExecutorStatus.CANCELLED,
            partial_evidence_available=False,
        )


def approved_replay_provider_declarations() -> SreReplayProviderDeclarations:
    return SreReplayProviderDeclarations.model_validate(
        {
            "scenario_id": SRE_REPLAY_SCENARIO_ID,
            "kubernetes": {
                "provider": "kubernetes",
                "mode": "sanitized_replay",
                "cluster": _APPROVED_CLUSTER,
                "namespaces": [MVP_NAMESPACE],
                "resources": sorted(_APPROVED_KUBERNETES_RESOURCES),
                "verbs": sorted(_READ_ONLY_VERBS),
            },
            "prometheus": {
                "provider": "prometheus",
                "mode": "sanitized_replay",
                "query_names": ["slo:burn_rate_5m", "slo:error_ratio_5m", "stage_ingress_request_rate_5m"],
                "query_allowlist": sorted(_APPROVED_PROMETHEUS_QUERIES),
            },
            "gitops": {
                "provider": "gitops",
                "mode": "sanitized_replay",
                "repository": "DimitryZH/sre-platform",
                "ref": "main",
                "paths": sorted(_APPROVED_GITOPS_PATHS),
                "actions": sorted(_READ_ONLY_GITOPS_ACTIONS),
            },
            "recovery_observation": {
                "provider": "recovery_observation",
                "mode": "sanitized_replay",
                "optional": True,
                "actions": sorted(_READ_ONLY_RECOVERY_ACTIONS),
                "claims_live_recovery": False,
            },
        }
    )


def approved_replay_provider_declarations_json() -> str:
    return json.dumps(
        approved_replay_provider_declarations().model_dump(mode="json"),
        sort_keys=True,
        separators=(",", ":"),
    )


def parse_replay_provider_declarations(raw_json: str) -> SreReplayProviderDeclarations:
    parsing_failed = False
    try:
        payload = json.loads(raw_json)
        if not isinstance(payload, dict) or first_unsafe_string(payload) is not None:
            raise ValueError("unsafe replay declaration")
        declarations = SreReplayProviderDeclarations.model_validate(payload)
    except (TypeError, ValueError, json.JSONDecodeError, ValidationError):
        parsing_failed = True
        declarations = None
    if parsing_failed or declarations is None:
        raise ValueError("SRE replay executor configuration is invalid")
    return declarations


def replay_declaration_failure(declaration: SreReplayProviderDeclarations) -> str | None:
    if declaration.scenario_id != SRE_REPLAY_SCENARIO_ID:
        return "scenario"
    kubernetes = declaration.kubernetes
    if (
        kubernetes.cluster != _APPROVED_CLUSTER
        or kubernetes.namespaces != [MVP_NAMESPACE]
        or set(kubernetes.resources) != _APPROVED_KUBERNETES_RESOURCES
        or set(kubernetes.verbs) != _READ_ONLY_VERBS
        or _contains_write_hint(kubernetes.verbs)
        or _contains_wildcard([*kubernetes.resources, *kubernetes.verbs])
    ):
        return "kubernetes"
    prometheus = declaration.prometheus
    if (
        set(prometheus.query_allowlist) != _APPROVED_PROMETHEUS_QUERIES
        or prometheus.query_names != ["slo:burn_rate_5m", "slo:error_ratio_5m", "stage_ingress_request_rate_5m"]
        or _contains_wildcard(prometheus.query_allowlist)
        or any("{" in query and 'exported_namespace="online-shop-stage"' not in query for query in prometheus.query_allowlist)
    ):
        return "prometheus"
    gitops = declaration.gitops
    if (
        gitops.repository != "DimitryZH/sre-platform"
        or gitops.ref != "main"
        or set(gitops.paths) != _APPROVED_GITOPS_PATHS
        or set(gitops.actions) != _READ_ONLY_GITOPS_ACTIONS
        or _contains_write_hint(gitops.actions)
        or _contains_wildcard([*gitops.paths, *gitops.actions])
    ):
        return "gitops"
    recovery = declaration.recovery_observation
    if recovery is None:
        return None
    if (
        not recovery.optional
        or recovery.claims_live_recovery
        or set(recovery.actions) != _READ_ONLY_RECOVERY_ACTIONS
        or _contains_write_hint(recovery.actions)
    ):
        return "recovery"
    return None


def validate_replay_command(command: StartInvestigationCommand) -> None:
    scope = command.request.scope
    if (
        command.request.constraints.read_only is not True
        or command.request.constraints.allow_mutation is not False
        or command.request.constraints.require_human_closeout is not True
        or set(command.request.requested_capabilities) != REQUIRED_CAPABILITIES
        or scope.cluster != _APPROVED_CLUSTER
        or scope.namespace != MVP_NAMESPACE
        or scope.workload != MVP_WORKLOAD
        or scope.rollout != MVP_ROLLOUT
        or scope.gitops_application != MVP_GITOPS_APPLICATION
    ):
        raise SreReplayRejected("SRE replay command is outside the approved scope")


def build_replay_result(
    command: StartInvestigationCommand,
    declarations: SreReplayProviderDeclarations,
) -> InvestigationResult:
    fixture = deepcopy(_SANITIZED_REPLAY_FIXTURE)
    fixture["result_id"] = "result-" + hashlib.sha256(_command_semantic_identity(command).encode("utf-8")).hexdigest()[:16]
    fixture["task_id"] = command.task_id
    fixture["attempt_id"] = command.attempt_id
    fixture["executor_id"] = SRE_REPLAY_EXECUTOR_ID
    fixture["evidence"] = [
        {
            **item,
            "reference": f"sre-platform://replay/{SRE_REPLAY_SCENARIO_ID}/{item['evidence_id']}",
        }
        for item in fixture["evidence"]
    ]
    fixture["limitations"].append(
        "Approved read-only scope: cluster sre-platform-staging, namespace online-shop-stage, workload frontend, rollout frontend, GitOps application online-shop-stage."
    )
    fixture["limitations"].append(
        "Prometheus replay query allowlist: " + ", ".join(declarations.prometheus.query_names) + "."
    )
    return InvestigationResult.model_validate(fixture)


def _contains_write_hint(values: list[str]) -> bool:
    return any(any(hint in value.lower() for hint in _WRITE_HINTS) for value in values)


def _contains_wildcard(values: list[str]) -> bool:
    return any("*" in value or value in {"all", "cluster-wide"} for value in values)


def _command_semantic_identity(command: StartInvestigationCommand) -> str:
    return json.dumps(command.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))


_SANITIZED_REPLAY_FIXTURE = {
    "schema_version": "1.0",
    "result_id": "result-placeholder",
    "task_id": "task-placeholder",
    "attempt_id": "attempt-placeholder",
    "executor_id": SRE_REPLAY_EXECUTOR_ID,
    "status": "succeeded",
    "summary": (
        "Sanitized replay evidence for the approved staging frontend contract is consistent with an elevated "
        "SLO error-ratio investigation path. This is replay validation only, not live staging or production validation."
    ),
    "findings": [
        {
            "finding_id": "finding-stage-slo-signal",
            "severity": "high",
            "confidence": "medium",
            "classification": "inference",
            "statement": (
                "The approved replay contract links frontend stage failure-path traffic to elevated SLO signals "
                "through bounded Prometheus and ingress evidence references."
            ),
            "evidence_ids": ["evidence-prometheus-error-ratio", "evidence-prometheus-burn-rate", "evidence-kubernetes-ingress"],
            "limitations": ["The finding is derived from sanitized replay evidence and does not prove a live condition."],
        }
    ],
    "probable_causes": [
        {
            "cause_id": "cause-controlled-stage-failure-path",
            "confidence": "medium",
            "statement": "Controlled requests to the approved stage failure path are the likely replay cause for the elevated SLO signals.",
            "evidence_ids": ["evidence-gitops-stage-overlay", "evidence-kubernetes-ingress", "evidence-prometheus-error-ratio"],
        }
    ],
    "evidence": [
        {
            "evidence_id": "evidence-kubernetes-rollout",
            "type": "kubernetes_read_fixture",
            "source": "sre_platform_observed",
            "reference": "placeholder",
            "supports": ["finding-stage-slo-signal"],
            "does_not_prove": "It does not prove live rollout health or recovery.",
        },
        {
            "evidence_id": "evidence-kubernetes-ingress",
            "type": "kubernetes_read_fixture",
            "source": "sre_platform_observed",
            "reference": "placeholder",
            "supports": ["finding-stage-slo-signal", "cause-controlled-stage-failure-path"],
            "does_not_prove": "It does not prove live ingress routing.",
        },
        {
            "evidence_id": "evidence-prometheus-error-ratio",
            "type": "prometheus_query_fixture",
            "source": "sre_platform_observed",
            "reference": "placeholder",
            "supports": ["finding-stage-slo-signal", "cause-controlled-stage-failure-path"],
            "does_not_prove": "It does not prove current SLO state.",
        },
        {
            "evidence_id": "evidence-prometheus-burn-rate",
            "type": "prometheus_query_fixture",
            "source": "sre_platform_observed",
            "reference": "placeholder",
            "supports": ["finding-stage-slo-signal"],
            "does_not_prove": "It does not prove current burn-rate state.",
        },
        {
            "evidence_id": "evidence-gitops-stage-overlay",
            "type": "gitops_read_fixture",
            "source": "sre_platform_observed",
            "reference": "placeholder",
            "supports": ["cause-controlled-stage-failure-path"],
            "does_not_prove": "It does not prove live Argo CD sync or cluster state.",
        },
        {
            "evidence_id": "evidence-recovery-observation",
            "type": "recovery_observation_fixture",
            "source": "unavailable",
            "reference": "placeholder",
            "supports": [],
            "does_not_prove": "Recovery was not observed and must remain SRE-owned.",
        },
    ],
    "limitations": [
        "Replay/fixture validation only; no live Kubernetes, Prometheus, GitOps, recovery, staging, or production validation was performed.",
        "No cluster access, model call, HolmesGPT invocation, remediation, rollout mutation, or GitOps write occurred.",
        "PostgreSQL remains the durable source of truth; GitHub publication is a separate opt-in path.",
    ],
    "recommendations": [
        {
            "recommendation_id": "rec-review-stage-scope",
            "type": "operator_action",
            "statement": (
                "Use the SRE-owned staging procedure to verify live symptoms and recovery before treating the replay finding "
                "as an operational conclusion."
            ),
            "requires_human_action": True,
            "executes_remediation": False,
        }
    ],
    "recovery_status": "not_checked",
    "human_review": {"required": True, "status": "pending", "reference": None},
    "github_references": [
        {
            "type": "issue",
            "url": "https://github.com/DimitryZH/ai-operations-platform/issues/55",
        }
    ],
}
