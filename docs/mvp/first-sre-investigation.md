# First SRE Investigation MVP Contract

## Status And Scope

This document defines the implementation contract for the first bounded,
read-only SRE investigation MVP of the AI Operations Platform.

It is a product-neutral design contract only. It does not implement the control
plane, select a persistence product, select a transport, select a hosting
platform, select an AI model, select an investigator framework, deploy an
executor, execute the orchestrator acceptance benchmark, or validate any
production SRE Platform behavior.

The MVP boundary follows the accepted roadmap, ADR 0001, and orchestrator
acceptance benchmark:

```text
Controlled staging failure or accepted investigation request
-> normalized investigation input
-> durable task creation
-> durable attempt creation
-> capability verification
-> read-only executor invocation
-> evidence collection and analysis
-> structured investigation result
-> durable GitHub reference
-> human review
-> explicit task closeout
```

The first implementation must stay sequential, read-only, GitHub-auditable,
and replaceable at the executor boundary. The SRE Platform remains responsible
for its environments, controlled failures, rollout behavior, SLO validation,
rollback, recovery, and operational evidence. The AI Operations Platform
remains responsible for durable request, task, attempt, executor, result, and
evidence identities; capability verification; executor invocation; structured
results; durable references; and human-review boundaries.

## Authoritative Inputs

AI Operations Platform inputs:

- [Roadmap](../roadmap.md)
- [ADR 0001: Primary Orchestrator Foundation](../adr/0001-primary-orchestrator-foundation.md)
- [Orchestrator Acceptance Benchmark](../benchmarks/orchestrator-acceptance-benchmark.md)
- GitHub issue
  [#21](https://github.com/DimitryZH/ai-operations-platform/issues/21)
- merged PR
  [#20](https://github.com/DimitryZH/ai-operations-platform/pull/20),
  merge commit `8e888b8cd0ad8ca5530fad1cad6891c9a9a39620`

SRE Platform repository state inspected for this contract:

- repository: `DimitryZH/sre-platform`
- branch: `main`
- inspected commit: `aecd1adaa8ba72a5a44453e805ae2a57e5f7731a`
- inspection mode: repository files only; no SRE Platform resources were
  modified, deployed, executed, or tested.

SRE Platform references used:

- `environments/stage/argocd/apps/online-shop-stage.yaml`
- `environments/stage/values/platform.yaml`
- `charts/platform/templates/frontend-rollout.yaml`
- `charts/platform/templates/frontend-slo-check-analysis-template.yaml`
- `charts/platform/templates/frontend-ingress.yaml`
- `charts/platform/templates/break-ingress.yaml`
- `charts/platform/templates/break-backend.yaml`
- `charts/platform/templates/prometheus-rules.yaml`
- `charts/platform/values.yaml`
- `temp-stage-baseline-live.yaml`
- `temp-stage-failure-live.yaml`
- `temp-stage-prom-precheck.yaml`
- `k6/README.md`
- `k6/k8s/job-baseline.yaml`
- `k6/k8s/job-failure-10.yaml`
- `k6/k8s/job-failure-50.yaml`
- `docs/evidence/slo_gated_rollout_evidence_dev.md`
- `docs/evidence/load-runs/*`

## Controlled Staging Scenario

### Repository-Verified Scenario

The exact staging scenario identified from the current SRE Platform repository
is:

```text
Environment: staging
Namespace: online-shop-stage
Argo CD application: online-shop-stage
Helm release: online-shop-stage
Service/workload under investigation: frontend
Rollout resource: frontend
Stable service: frontend
Canary service: frontend-canary
Ingress: online-shop-frontend
Ingress path prefix: /stage
Controlled failure path: /stage/break
SLO analysis template: frontend-slo-check
Primary SLO signals: slo:error_ratio_5m, slo:burn_rate_5m
Prometheus endpoint inside cluster:
  http://monitoring-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
```

`environments/stage/argocd/apps/online-shop-stage.yaml` defines the stage Argo
CD application targeting namespace `online-shop-stage`, using
`charts/platform` from `DimitryZH/sre-platform` `main` with
`environments/stage/values/platform.yaml`.

`environments/stage/values/platform.yaml` defines the stage overlay:

- `global.namespace: online-shop-stage`
- `frontend.replicaCount: 1`
- hostless ingress with `frontend.ingress.pathPrefix: /stage`
- `rollouts.enabled: true`
- frontend, cart, checkout, and payment image tags set to `v0.10.4`

`charts/platform/templates/frontend-rollout.yaml` defines a frontend Argo
Rollout with canary steps:

- set canary weight to `10`
- pause `7m`
- run analysis template `frontend-slo-check`
- set canary weight to `50`
- pause `2m`
- run analysis template `frontend-slo-check`
- set canary weight to `100`

`charts/platform/templates/frontend-slo-check-analysis-template.yaml` defines
two Prometheus-backed checks:

- `burn-rate-5m`: query `slo:burn_rate_5m`, success when `result[0] <= 10`,
  failure when `result[0] > 10`, interval `30s`, count `5`
- `error-ratio-5m`: query `slo:error_ratio_5m`, success when
  `result[0] <= 0.02`, failure when `result[0] > 0.02`, interval `30s`,
  count `5`

`temp-stage-baseline-live.yaml` defines a temporary staging pod named
`stage-baseline-live` in `online-shop-stage` that repeatedly issues HTTP
requests to:

```text
http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/stage
```

The repository-defined healthy baseline start mechanism is to apply this
manifest in the SRE Platform environment. That action is owned by the SRE
Platform and was not performed by this issue.

`temp-stage-failure-live.yaml` defines a temporary staging pod named
`stage-failure-live` in `online-shop-stage` that repeatedly issues HTTP
requests to:

```text
http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/stage/break
```

The repository-defined controlled-failure start mechanism is to apply this
manifest in the SRE Platform environment while the baseline denominator traffic
is present. That action is owned by the SRE Platform and was not performed by
this issue.

`charts/platform/templates/break-ingress.yaml` maps the stage break path to
the `break-500` service and rewrites it to `/status/500`.
`charts/platform/templates/break-backend.yaml` defines that `break-500`
backend. The chart default enables this backend with
`mccutchen/go-httpbin:v2.14.0`, which provides deterministic HTTP status
endpoints.

`temp-stage-prom-precheck.yaml` defines a temporary staging pod named
`stage-prom-precheck` in `online-shop-stage` that queries Prometheus for:

- `slo:error_ratio_5m`
- `slo:burn_rate_5m`
- `sum(rate(nginx_ingress_controller_requests{exported_namespace="online-shop-stage",status!=""}[5m]))`

These files provide a repository-defined staging mechanism for healthy
denominator traffic, controlled failure traffic, and SLO signal inspection.
This issue did not apply those manifests or verify their live runtime result.

### Failure Start And Restore Ownership

The SRE Platform owns starting and restoring this scenario. For future
implementation and demonstration, the expected SRE-owned actions are:

- start or identify healthy staging baseline traffic against `/stage`
- start controlled failure traffic against `/stage/break`
- observe elevated HTTP error ratio or burn-rate signals through Prometheus
- inspect rollout, pod, ingress, logs, GitOps, and SLO analysis state
- stop the controlled failure source
- restore or verify the stage environment according to SRE Platform procedures

The repository evidence suggests the temporary staging traffic sources can be
stopped by ending or deleting the corresponding temporary pods, because they
are standalone pods with `restartPolicy: Never`. When rollout state is part of
the scenario, implementation-time restoration must follow the SRE Platform's
owned rollout recovery procedure and confirm that the SLO window has cleared.

The AI Operations Platform MVP must not start the failure, stop pods, patch
rollouts, change GitOps configuration, deploy manifests, or independently
declare the real incident resolved. It may only accept a request that points at
the approved SRE Platform scenario and collect read-only evidence within the
approved scope.

### Expected Observable Symptoms

The expected observable symptoms for the future SRE-owned staging scenario are:

- increased request failures for the stage frontend path associated with
  `/stage/break`
- elevated `slo:error_ratio_5m`
- elevated `slo:burn_rate_5m`
- possible failed `frontend-slo-check` AnalysisRun during a canary step when
  the failure overlaps the analysis sampling window
- rollout state showing the current canary step, analysis result, abort,
  pause, or recovery state as applicable
- Kubernetes pod and workload state for the frontend and temporary stage
  traffic pods
- Argo CD application state for `online-shop-stage`
- GitOps references identifying the applied stage overlay and image tags
- application or ingress logs within the approved time range

These symptoms must be treated as expected future observables until confirmed
in the implementation run. The current repository includes dev evidence for
SLO-gated rollout behavior and load-run outcomes, but that dev evidence must
not be presented as live staging validation or production validation.

### Existing Validation Versus Assumptions

Existing SRE Platform validation evidence:

- Development-environment evidence documents SLO signal behavior, controlled
  load scenarios, rollout AnalysisRuns, abort behavior, and recovery evidence.
- k6 documentation maps `baseline`, `failure-10`, and `failure-50` scenarios
  to SLO-gated rollout validation in `online-shop-dev`.
- Load-run evidence includes dev baseline, failure, analysis run, rollout, and
  recovery artifacts.

Repository-verified staging implementation:

- The stage Argo CD application, stage values overlay, stage namespace,
  frontend rollout, stage path prefix, temporary baseline pod, temporary
  failure pod, and temporary Prometheus precheck pod exist in the inspected
  repository.

Implementation-time assumptions requiring confirmation:

- the stage Argo CD application is synced and healthy in the target cluster
- the hostless `/stage` and `/stage/break` paths route to the expected
  frontend behavior
- ingress metrics include `exported_namespace="online-shop-stage"` labels
- `slo:error_ratio_5m` and `slo:burn_rate_5m` evaluate for the staging
  traffic window
- the failure remains active long enough to overlap rollout analysis sampling
  when rollout behavior is part of the investigation
- the SRE Platform restore procedure returns stage to a clean, healthy state
- the future executor has read-only access to Kubernetes, Prometheus, logs,
  Argo Rollouts, and GitOps references for the approved stage scope

The SRE Platform production phase remains incomplete and unvalidated. This
MVP contract does not claim production rollout, production SLO validation,
production rollback, or production recovery completion.

## Workflow Boundary

The MVP separates the operational incident from the AI Operations task.

| Concern | Owner | MVP behavior |
| --- | --- | --- |
| Detection of operational condition | SRE Platform or operator | Supplies a bounded event or manual request. |
| Acceptance of investigation request | AI Operations Platform | Validates scope and creates durable task state. |
| Orchestration of investigation | AI Operations Platform | Creates attempts, verifies capabilities, dispatches one read-only executor. |
| Evidence collection | Executor through adapter | Reads only approved Kubernetes, Prometheus, rollout, GitOps, and logs evidence. |
| Probabilistic AI analysis | Executor | Produces findings with confidence, limitations, and evidence references. |
| Recovery verification | SRE Platform owns action; AI Operations may observe | Read-only observation only when requested and within approved scope. |
| Human review | Operator or reviewer | Accepts, rejects, or requests follow-up; recommendations are not executed. |
| AI Operations task closeout | AI Operations Platform plus human decision | Completed only after explicit human closeout. |
| Operational incident resolution | SRE Platform | Not closed automatically by this MVP. |

The AI Operations task begins when a normalized investigation request is
received. It ends only after the structured result and durable GitHub reference
are available and a human records an explicit closeout decision.

The MVP must not:

- remediate Kubernetes resources
- change rollout state
- modify GitOps configuration
- merge pull requests
- start or stop SRE Platform failure workloads
- declare the operational incident resolved
- close the SRE Platform incident or issue

## Supported MVP Triggers

The internal lifecycle supports two bounded entry paths.

### Operator-Triggered Investigation

This path is used for initial validation and demonstration. An operator submits
a known staging scenario using the normalized request contract. The external
entry mechanism is intentionally unspecified; it may later be a CLI, UI,
GitHub form, ChatOps command, API call, or another transport.

The operator-triggered path must:

- include a unique `request_id`
- identify `sre-platform`
- declare `environment: staging`
- scope the request to `online-shop-stage` and `frontend`
- provide an approved time range
- request only read-only capabilities
- preserve the original operator request as evidence

### Normalized Operational Event

This path represents a future alert or SLO event supplied by the SRE Platform.
It uses the same internal task, attempt, capability, evidence, output, and
human-review lifecycle as the operator-triggered path.

The external event source is not selected by this contract. Scheduled broad
log scanning, continuous autonomous discovery, and production-scale alert
routing are out of scope.

## Normalized Investigation Input

### Input Schema

The internal request contract is versioned JSON. Version `1.0` is the only
accepted schema version for the first MVP.

```json
{
  "schema_version": "1.0",
  "request_id": "req-20260813-stage-001",
  "source": {
    "type": "operator",
    "system": "sre-platform",
    "reference": "https://github.com/DimitryZH/ai-operations-platform/issues/21"
  },
  "scenario": {
    "type": "slo_investigation",
    "environment": "staging",
    "service": "frontend",
    "summary": "Investigate elevated HTTP error ratio during a controlled staging failure"
  },
  "scope": {
    "cluster": "sre-platform-staging",
    "namespace": "online-shop-stage",
    "workload": "frontend",
    "rollout": "frontend",
    "gitops_application": "online-shop-stage",
    "time_range": {
      "start": "2026-08-13T15:00:00Z",
      "end": "2026-08-13T15:20:00Z"
    }
  },
  "signal": {
    "status": "manual",
    "name": "frontend-stage-error-ratio",
    "fingerprint": "sre-platform-stage-frontend-20260813T150000Z",
    "observed_at": "2026-08-13T15:05:00Z",
    "references": [
      {
        "type": "prometheus_query",
        "name": "slo:error_ratio_5m"
      }
    ]
  },
  "requested_capabilities": [
    "kubernetes.read",
    "prometheus.query",
    "rollout.read",
    "gitops.read",
    "logs.read",
    "investigation.report"
  ],
  "constraints": {
    "read_only": true,
    "allow_mutation": false,
    "require_human_closeout": true
  }
}
```

### Field Rules

| Field | Required | Rule |
| --- | --- | --- |
| `schema_version` | Yes | Must equal `1.0`; unsupported versions are rejected. |
| `request_id` | Yes | Stable idempotency key supplied by the caller or generated before durable task creation. |
| `source.type` | Yes | Must be `operator` or `sre_event`. |
| `source.system` | Yes | Must equal `sre-platform` for this MVP. |
| `source.reference` | Optional | Durable link to the operator request, event, issue, or comment. |
| `scenario.type` | Yes | Must equal `slo_investigation`. |
| `scenario.environment` | Yes | Must equal `staging` for the first MVP. |
| `scenario.service` | Yes | Must equal `frontend` for the first MVP. |
| `scenario.summary` | Yes | Human-readable summary; must not contain secrets. |
| `scope.cluster` | Yes | Logical cluster/environment identifier; must not expose private endpoints or credentials. |
| `scope.namespace` | Yes | Must equal `online-shop-stage`. |
| `scope.workload` | Yes | Must equal `frontend`. |
| `scope.rollout` | Optional | Expected value `frontend` when rollout evidence is requested. |
| `scope.gitops_application` | Optional | Expected value `online-shop-stage` when GitOps evidence is requested. |
| `scope.time_range.start` | Yes | RFC 3339 timestamp. |
| `scope.time_range.end` | Yes | RFC 3339 timestamp later than `start`. |
| `signal.status` | Yes | Must be `firing`, `resolved`, or `manual`. |
| `signal.name` | Yes | Stable signal name for correlation. |
| `signal.fingerprint` | Yes | Duplicate-event key for equivalent alerts or manual runs. |
| `signal.observed_at` | Yes | RFC 3339 timestamp within or near the approved time range. |
| `signal.references` | Optional | Bounded public or sanitized references to source evidence. |
| `requested_capabilities` | Yes | Non-empty list of allowed capability identifiers. |
| `constraints.read_only` | Yes | Must be `true`. |
| `constraints.allow_mutation` | Yes | Must be `false`. |
| `constraints.require_human_closeout` | Yes | Must be `true`. |

### Validation And Rejection

The control plane must reject the request before task activation when:

- required fields are missing
- `schema_version` is unsupported
- source system is not `sre-platform`
- environment is not `staging`
- namespace, workload, rollout, or GitOps application scope is missing,
  ambiguous, or outside the first MVP
- the time range is missing, inverted, excessive, or unsafe
- requested capabilities include mutation or unsupported capabilities
- constraints do not require read-only execution and human closeout
- any example, reference, or summary contains credentials, tokens, private
  endpoints, raw secrets, or machine-specific paths

The initial implementation should allow a bounded time range of at most
60 minutes. Longer windows require a separate approval and are outside the
first demo target.

The original request or event must be preserved as immutable evidence after
redaction checks. Rejected requests must retain the rejection reason, timestamp,
and sanitized original input reference.

### Idempotency And Duplicates

`request_id` is the primary idempotency key. `signal.fingerprint` is the
duplicate-event key for repeated operational delivery of the same condition.

The control plane must not create uncontrolled duplicate work. Repeated input
with the same `request_id` must return the existing task reference. Repeated
input with a different `request_id` but same `signal.fingerprint` and
overlapping scope/time range must either attach to the existing task or create
a new task only through an explicit deduplication policy recorded in durable
state.

## Task And Attempt Identity Model

The conceptual relationship is:

```text
one normalized investigation request
-> one durable task
-> one or more sequential attempts
```

The MVP must retain explicit identifiers:

- `request_id`
- `task_id`
- `attempt_id`
- `executor_id`
- `result_id`
- `evidence_id`
- `github_reference_id`

Retry must create a new `attempt_id`. A failed, timed out, stale, cancelled,
or capability-rejected attempt must never be silently reused as a successful
attempt. A task in a terminal state must not create another attempt; further
investigation after terminal task closeout requires a new request and task.

### Task States

| State | Meaning | Initiator |
| --- | --- | --- |
| `RECEIVED` | Request was received and stored. | Intake boundary |
| `VALIDATED` | Request passed schema, scope, safety, and duplicate validation. | Control plane |
| `READY` | Durable task exists and an attempt may be created. | Control plane |
| `RUNNING` | At least one attempt is active. | Control plane |
| `AWAITING_HUMAN_REVIEW` | Structured result is available and workflow has stopped for review. | Control plane |
| `COMPLETED` | Human closeout accepted the AI Operations task result. | Human reviewer |
| `REJECTED` | Request cannot be accepted. | Control plane |
| `FAILED` | Task is closed unsuccessfully; no more attempts may be created on this task. | Control plane or human reviewer |
| `TIMED_OUT` | Task exceeded declared task-level budget and is closed; no more attempts may be created on this task. | Control plane |
| `CANCELLED` | Human or policy cancelled the task. | Human reviewer or control plane policy |

Permitted normal transitions:

```text
RECEIVED -> VALIDATED -> READY -> RUNNING -> AWAITING_HUMAN_REVIEW -> COMPLETED
```

Permitted exceptional transitions:

```text
RECEIVED -> REJECTED
VALIDATED -> REJECTED
READY -> FAILED
READY -> TIMED_OUT
READY -> CANCELLED
RUNNING -> READY
RUNNING -> FAILED
RUNNING -> TIMED_OUT
RUNNING -> CANCELLED
AWAITING_HUMAN_REVIEW -> COMPLETED
AWAITING_HUMAN_REVIEW -> READY
AWAITING_HUMAN_REVIEW -> FAILED
AWAITING_HUMAN_REVIEW -> CANCELLED
```

`READY -> TIMED_OUT` is allowed only when the task-level timeout budget is
exhausted before another attempt can be dispatched. `RUNNING -> READY` is
allowed only after the active attempt reaches a terminal non-success state and
the control plane records that retry is still permitted within the same task.
`AWAITING_HUMAN_REVIEW -> READY` is allowed only when a human reviewer rejects
the result but explicitly requests another investigation attempt under the
same validated request scope. If a task reaches `FAILED`, `TIMED_OUT`,
`CANCELLED`, `REJECTED`, or `COMPLETED`, retry on that task is no longer
allowed.

Each transition must retain:

- transition timestamp
- actor or component
- reason
- previous state
- next state
- related attempt, capability, result, evidence, or GitHub reference when
  applicable

Terminal states are `COMPLETED`, `REJECTED`, `FAILED`, `TIMED_OUT`, and
`CANCELLED`. Terminal tasks must not be mutated except to append audit
metadata, human-review comments, or linked GitHub references.

### Attempt States

| State | Meaning | Initiator |
| --- | --- | --- |
| `CREATED` | Attempt identity exists and is linked to the parent task. | Control plane |
| `CAPABILITY_CHECKED` | Required capabilities were declared and verified. | Control plane and adapter |
| `DISPATCHED` | Adapter accepted the read-only investigation request. | Control plane |
| `RUNNING` | Executor is actively collecting or analyzing evidence. | Adapter or executor |
| `SUCCEEDED` | Executor produced a schema-valid result, including a schema-valid partial result. | Adapter |
| `CAPABILITY_REJECTED` | Required capability was missing, ambiguous, unverifiable, incorrectly scoped, or write-capable. | Control plane |
| `DISPATCH_FAILED` | Adapter did not accept dispatch. | Control plane |
| `FAILED` | Executor or adapter failed with a non-timeout error. | Adapter or control plane |
| `TIMED_OUT` | Attempt exceeded declared attempt budget. | Control plane |
| `STALE` | Attempt lost heartbeat, status, or observable executor continuity and is terminal for that attempt. | Control plane |
| `CANCELLED` | Attempt was cancelled before terminal result. | Human reviewer or control plane |

Permitted normal transitions:

```text
CREATED -> CAPABILITY_CHECKED -> DISPATCHED -> RUNNING -> SUCCEEDED
```

Permitted exceptional transitions:

```text
CREATED -> CAPABILITY_REJECTED
CREATED -> CANCELLED
CREATED -> STALE
CAPABILITY_CHECKED -> DISPATCH_FAILED
CAPABILITY_CHECKED -> CANCELLED
CAPABILITY_CHECKED -> STALE
DISPATCHED -> CANCELLED
DISPATCHED -> FAILED
DISPATCHED -> TIMED_OUT
DISPATCHED -> STALE
RUNNING -> FAILED
RUNNING -> TIMED_OUT
RUNNING -> STALE
RUNNING -> CANCELLED
```

Terminal attempt states are `SUCCEEDED`, `CAPABILITY_REJECTED`,
`DISPATCH_FAILED`, `FAILED`, `TIMED_OUT`, `STALE`, and `CANCELLED`.

`STALE` is a terminal state for the affected attempt, not a non-terminal
reconciliation state. After marking an attempt `STALE`, the control plane must
reconcile durable task state. If retry remains permitted, the parent task moves
from `RUNNING` to `READY`; otherwise it moves from `RUNNING` to terminal
`FAILED` or `TIMED_OUT` according to the task budget and failure reason.

When an attempt reaches `CAPABILITY_REJECTED`, `DISPATCH_FAILED`, `FAILED`,
`TIMED_OUT`, `STALE`, or `CANCELLED` and the same task can continue, the parent
task must move to `READY` with a recorded retry decision. The next execution
must use a new `attempt_id` and must repeat capability verification. If the
parent task moves to terminal `FAILED`, `TIMED_OUT`, or `CANCELLED`, retry
requires a new task. After a control-plane or executor interruption, the
control plane must reconcile durable task and attempt state before any new
dispatch. It must not infer success from dispatch acceptance, session
creation, or incomplete executor output.

## Required Executor Capabilities

The first executor contract includes only capabilities required for the
repository-verified staging scenario.

| Capability | Class | Scope | Verification method | Failure behavior |
| --- | --- | --- | --- | --- |
| `kubernetes.read` | Required | Read pod, workload, event, service, ingress, and namespace metadata for `online-shop-stage` only. | Adapter declares read-only Kubernetes access; control plane verifies target namespace restriction and denies write verbs. | Immediate state: task `READY`, attempt `CAPABILITY_REJECTED`; a new attempt is allowed only after capability scope is corrected and approved. |
| `prometheus.query` | Required | Query approved Prometheus expressions for the approved time range. | Adapter declares query endpoint scope; control plane verifies queries are read-only and bounded to approved SLO/ingress signals. | Immediate state: task `READY`, attempt `CAPABILITY_REJECTED`; a new attempt is allowed only after query capability is corrected and approved. |
| `rollout.read` | Required | Read Argo Rollouts resource `frontend` and related AnalysisRuns in `online-shop-stage`. | Adapter declares rollout read scope; control plane verifies no patch, promote, abort, retry, or undo verbs. | Immediate state: task `READY`, attempt `CAPABILITY_REJECTED`; a new attempt is allowed only after rollout read scope is corrected and approved. |
| `gitops.read` | Required | Read GitOps metadata for Argo CD application `online-shop-stage` and repository refs. | Adapter declares read-only app/repository metadata access. | Immediate state: task `READY`, attempt `CAPABILITY_REJECTED`; a new attempt is allowed only after GitOps read scope is corrected and approved. |
| `logs.read` | Required | Read bounded frontend, ingress, and relevant pod logs within the approved time range. | Adapter declares log source and retention limits; control plane verifies no exec or mutation scope. | Immediate state: task `READY`, attempt `CAPABILITY_REJECTED`; a new attempt is allowed only after log read scope is corrected and approved. |
| `investigation.report` | Required | Produce normalized result JSON and bounded human-readable summary. | Adapter declares schema version support and result validation path. | Immediate state for malformed or missing report: task `READY`, attempt `FAILED`; a new attempt is allowed only after adapter correction or human-approved retry. |
| `recovery.observe` | Optional | Read-only observation of recovery signals when SRE Platform restore has already occurred. | Same read-only checks as evidence collection. | Absence produces explicit `recovery_status: not_checked`; it must not fail the base investigation. |
| `raw_artifact.reference` | Optional | Reference sanitized raw logs or artifacts without committing large content. | Verify artifact reference is durable and sanitized. | Absence is recorded as a limitation. |

Unsupported capabilities for the first MVP:

- broad log scanning outside the approved time range
- continuous autonomous discovery
- multi-cluster investigation
- production-scale alert routing
- multiple executor dispatch
- patch or pull request preparation
- autonomous remediation

Explicitly prohibited mutation capabilities:

- `kubernetes.write`
- `rollout.promote`
- `rollout.abort`
- `rollout.retry`
- `gitops.write`
- `deployment.write`
- `incident.close`
- `pull_request.merge`
- secret read beyond the minimum needed to authenticate the approved read-only
  data sources

The control plane must fail closed before dispatch when any required
capability is missing, ambiguous, unverifiable, incorrectly scoped, broader
than the approved target, or write-capable where read-only access is required.

HolmesGPT remains an unselected, read-only, replaceable candidate. This
contract does not claim that HolmesGPT or any other candidate satisfies these
capabilities.

## Product-Neutral Executor Adapter Contract

The adapter boundary separates the control plane from a replaceable SRE
investigator. It is conceptual and product-neutral; concrete protocol, SDK,
transport, authentication, hosting, and model choices remain unresolved.

### Operations

| Operation | Purpose | Required behavior |
| --- | --- | --- |
| `describe_capabilities` | Return declared capabilities and target scope. | Must include `executor_id`, schema versions, capability IDs, read/write scope, verification hints, and unsupported operations. |
| `start_investigation` | Dispatch one read-only attempt. | Must accept `request_id`, `task_id`, `attempt_id`, approved scope, time range, capabilities, constraints, and evidence policy. |
| `get_status` | Report attempt status. | Must distinguish accepted, queued, running, succeeded, failed, timed out, stale, and cancelled. |
| `get_result` | Return normalized result. | Must return schema-valid result JSON, including `status: partial` when evidence is incomplete but reportable, or a structured error with raw-output reference. |
| `cancel_attempt` | Request bounded cancellation. | Must stop future work when possible and report whether already-collected evidence is partial. |

### Request Metadata

Each adapter call must include:

- `schema_version`
- `request_id`
- `task_id`
- `attempt_id`
- `executor_id`
- approved capability set
- approved scope
- approved time range
- correlation timestamp
- timeout budget
- evidence retention policy
- read-only constraints
- GitHub reference target

### Status, Timeout, Retry, And Cancellation

The adapter must not report attempt `SUCCEEDED` until it has produced a
schema-valid result. A schema-valid result with `status: partial` is still an
attempt `SUCCEEDED`; it moves the parent task to `AWAITING_HUMAN_REVIEW`
because the partial investigation is reviewable but incomplete. Malformed
output, missing required result fields, or adapter inability to normalize
executor output produces attempt `FAILED` and immediate parent task `READY`
when retry remains permitted. A timeout produces attempt `TIMED_OUT`, not
`FAILED`, unless the failure is known and non-timeout. Lost heartbeat or
unobservable executor state produces terminal attempt `STALE`.

Retry is a control-plane decision and must create a new attempt. The adapter
must not silently retry in a way that hides attempt boundaries.

Cancellation is best effort. A cancelled attempt must preserve collected
evidence references. If cancellation happens before a schema-valid result is
available, the attempt is `CANCELLED`; if a schema-valid partial result already
exists, the attempt may be `SUCCEEDED` and the result status remains
`partial`.

### Structured Error Categories

Adapter errors must normalize to:

- `capability_missing`
- `capability_ambiguous`
- `capability_scope_invalid`
- `dispatch_rejected`
- `executor_unavailable`
- `timeout`
- `stale`
- `result_malformed`
- `evidence_incomplete`
- `authentication_blocked`
- `authorization_blocked`
- `unsafe_scope`
- `unknown`

Raw executor output may be preserved as a sanitized artifact reference. The
normalized result must not require publishing large raw logs, credentials,
private endpoints, customer data, or machine-specific paths.

## Evidence Requirements

Each MVP run must preserve enough evidence to understand and reproduce the
investigation without exposing sensitive data.

Required evidence categories:

- original normalized request
- task timeline
- attempt timeline
- capability declaration
- capability verification result
- Kubernetes workload, service, ingress, pod, and event state
- Argo Rollouts `frontend` state and related AnalysisRuns
- Prometheus query results for approved SLO and ingress metrics
- relevant logs within the approved time range
- Argo CD application and GitOps references for `online-shop-stage`
- executor request and normalized response
- raw executor output reference when retained
- identified evidence gaps
- limitations and uncertainty
- recovery-verification evidence when available
- durable GitHub issue, comment, artifact, commit, or PR reference
- human-review decision

Evidence provenance classifications:

| Classification | Meaning |
| --- | --- |
| `sre_platform_observed` | Read directly from approved SRE Platform runtime or repository evidence. |
| `operator_provided` | Supplied by the operator or source event. |
| `ai_interpretation` | Generated interpretation or summary. |
| `inference` | Conclusion derived from observed evidence and explicitly marked as inference. |
| `unavailable` | Evidence expected by the contract but not available for this attempt. |

Findings must reference evidence IDs. The result must not present an inference
as an observed fact. Unavailable evidence must be explicit and must affect the
result status or limitations when material.

Do not commit large raw logs, secrets, credentials, customer data, private
endpoints, private runtime state, raw session databases, or machine-specific
paths.

## Structured Output Schema

### Result Schema

Version `1.0` is the only accepted result schema version for the first MVP.

```json
{
  "schema_version": "1.0",
  "result_id": "result-20260813-stage-001",
  "task_id": "task-20260813-stage-001",
  "attempt_id": "attempt-20260813-stage-001-a1",
  "executor_id": "executor-readonly-sre-001",
  "status": "succeeded",
  "summary": "Controlled stage failure traffic is associated with elevated frontend SLO error signals during the approved time range.",
  "findings": [
    {
      "finding_id": "finding-001",
      "severity": "high",
      "confidence": "medium",
      "classification": "inference",
      "statement": "The elevated error ratio is probably associated with requests to the approved stage failure path.",
      "evidence_ids": ["evidence-prom-er5", "evidence-ingress-logs"],
      "limitations": ["Failure traffic source was identified by request scope, not started by the AI Operations Platform."]
    }
  ],
  "probable_causes": [
    {
      "cause_id": "cause-001",
      "confidence": "medium",
      "statement": "Controlled failure endpoint traffic is the likely cause of the SLO burn-rate increase.",
      "evidence_ids": ["evidence-prom-br5", "evidence-request"]
    }
  ],
  "evidence": [
    {
      "evidence_id": "evidence-prom-br5",
      "type": "prometheus_query",
      "source": "sre_platform_observed",
      "reference": "github-issue-comment-or-artifact-reference",
      "supports": ["finding-001", "cause-001"],
      "does_not_prove": "It does not prove recovery or production behavior."
    }
  ],
  "limitations": [
    "Recovery was not checked during this attempt."
  ],
  "recommendations": [
    {
      "recommendation_id": "rec-001",
      "type": "operator_action",
      "statement": "Review SRE Platform rollout and stop the controlled failure source according to the SRE-owned procedure.",
      "requires_human_action": true,
      "executes_remediation": false
    }
  ],
  "recovery_status": "not_checked",
  "human_review": {
    "required": true,
    "status": "pending",
    "reference": null
  },
  "github_references": [
    {
      "type": "issue_comment",
      "url": "https://github.com/DimitryZH/ai-operations-platform/issues/21#issuecomment-placeholder"
    }
  ]
}
```

### Result Field Rules

| Field | Required | Rule |
| --- | --- | --- |
| `schema_version` | Yes | Must equal `1.0`. |
| `result_id` | Yes | Durable identifier for this result. |
| `task_id` | Yes | Must match parent task. |
| `attempt_id` | Yes | Must match producing attempt. |
| `executor_id` | Yes | Must match adapter/executor identity. |
| `status` | Yes | Must be `succeeded`, `partial`, or `failed`. |
| `summary` | Yes | Human-readable summary without secrets or unsupported claims. |
| `findings` | Yes | Array; may be empty only when status is `partial` or `failed` with explanation. |
| `probable_causes` | Yes | Array; may be empty with explicit uncertainty. |
| `evidence` | Yes | Array of evidence records; each finding must reference evidence IDs. |
| `limitations` | Yes | Explicit limitations, gaps, and uncertainty. |
| `recommendations` | Yes | Operator recommendations only; no execution. |
| `recovery_status` | Yes | Must be `not_checked`, `still_failing`, `recovered`, or `unknown`. |
| `human_review` | Yes | Must require human review for the first MVP. |
| `github_references` | Yes | Durable GitHub references for the result or evidence package. |

Finding severity values:

- `critical`
- `high`
- `medium`
- `low`
- `informational`

Confidence values:

- `high`
- `medium`
- `low`
- `unknown`

Partial-result behavior:

- use result `status: partial`
- include evidence collected before the failure
- include missing evidence in `limitations`
- do not claim diagnosis completeness
- set the producing attempt to `SUCCEEDED` only when the partial result is
  schema-valid
- set the parent task to `AWAITING_HUMAN_REVIEW`
- preserve adapter or executor error category when the partial result was
  caused by bounded evidence or executor limitations

Empty-result behavior:

- use `status: failed` when no useful evidence or findings can be produced
- preserve request, capability, dispatch, and error evidence
- set the producing attempt to `FAILED`
- set the parent task to `READY` when retry remains permitted; otherwise set
  the parent task to terminal `FAILED`

Recommendations may propose operator actions, investigation follow-up, or
SRE-owned restore checks. They must not execute remediation, change rollout
state, modify GitOps configuration, merge pull requests, or close the
operational incident.

## Failure Handling Matrix

The matrix records deterministic immediate states. Later retry or closeout
decisions are separate transitions and must be recorded with the authorizing
actor or condition. `None` means no lifecycle object exists for that incoming
delivery, so no task or attempt state transition is created.

| Case | Immediate task state | Immediate attempt state | Allowed subsequent transition | Authorizing actor or condition | Preserved evidence | Operator-visible outcome |
| --- | --- | --- | --- | --- | --- | --- |
| Invalid input | `REJECTED` | None | None on this task; submit a new request to investigate again. | New valid request from operator or event source. | Sanitized input and rejection reason. | Request rejected before activation. |
| Duplicate request | `REJECTED` | None | None on the duplicate delivery; attach duplicate reference to existing task audit trail. | Control-plane deduplication policy. | Duplicate key, rejection reason, and existing task reference. | Existing task reference returned unchanged; no attempt is created for the duplicate delivery. |
| Missing required capability | `READY` | `CAPABILITY_REJECTED` | `READY -> RUNNING` through a new attempt. | Corrected capability declaration and control-plane approval. | Capability declaration, verification result, reason. | Fail-closed before dispatch. |
| Incorrectly scoped capability | `READY` | `CAPABILITY_REJECTED` | `READY -> RUNNING` through a new attempt. | Corrected least-privilege scope and control-plane approval. | Approved scope, declared scope, mismatch. | Fail-closed before dispatch. |
| Write-capable capability where read-only is required | `READY` | `CAPABILITY_REJECTED` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` if least-privilege correction is not allowed. | Human approval of corrected read-only capability, or control-plane policy to close as failed. | Capability scope and policy violation. | Security failure before dispatch. |
| Unavailable executor | `READY` | `DISPATCH_FAILED` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` if no executor is available within budget. | Executor availability restored, approved alternate executor, or timeout/budget policy. | Adapter status and dispatch error. | No execution claimed. |
| Dispatch failure | `READY` | `DISPATCH_FAILED` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` if dispatch cannot be corrected. | Control-plane retry policy after dispatch cause is corrected. | Dispatch request and error category. | Attempt did not start. |
| Executor timeout | `READY` | `TIMED_OUT` | `READY -> RUNNING` through a new attempt, or `READY -> TIMED_OUT` when task-level budget is exhausted. | Control-plane timeout budget and human approval when required by policy. | Timeout budget, last status, partial evidence. | Explicit non-success outcome; no completion claimed. |
| Executor loss after dispatch | `READY` | `STALE` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` when state cannot be reconciled safely. | Control-plane reconciliation confirms no active executor and retry is safe. | Last heartbeat/status and stale rule. | Attempt stale; no success inferred. |
| Stale attempt | `READY` | `STALE` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` when stale state cannot be safely superseded. | Stale-attempt detector and reconciliation policy. | Staleness detection evidence. | Requires recovery or supersession. |
| Malformed executor result | `READY` | `FAILED` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` if adapter correction is not available. | Adapter correction, schema fix, or human-approved retry. | Raw output reference and schema validation error. | Result rejected; no partial success claimed. |
| Incomplete evidence with schema-valid partial result | `AWAITING_HUMAN_REVIEW` | `SUCCEEDED` | `AWAITING_HUMAN_REVIEW -> COMPLETED`, `AWAITING_HUMAN_REVIEW -> READY`, or `AWAITING_HUMAN_REVIEW -> FAILED`. | Human accepts partial result, requests another attempt, or rejects closeout. | Evidence gaps, limitations, and partial result. | Partial investigation result is reviewable; no unsupported diagnosis. |
| Incomplete evidence without schema-valid result | `READY` | `FAILED` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` if evidence cannot be collected within scope. | Evidence source restored, scope still valid, and human-approved retry if required. | Evidence gaps and executor error. | Failed attempt; no reviewable result claimed. |
| Control-plane restart during active attempt | `READY` | `STALE` | `READY -> RUNNING` through a new attempt, or `READY -> FAILED` if reconciliation cannot prove safe supersession. | Durable-state reconciliation confirms active attempt cannot be observed safely. | Pre/post restart state, last heartbeat, and recovery decision. | Active attempt is bounded as stale before retry. |
| Repeated delivery of same operational event | `REJECTED` | None | None on the repeated delivery; attach repeated event reference to existing task audit trail. | Control-plane deduplication policy based on `request_id` or `signal.fingerprint`. | Fingerprint, request IDs, dedupe decision, rejection reason, and existing task reference. | Existing task reference returned unchanged; no attempt is created for repeated delivery. |
| Human rejection requesting another attempt | `READY` | `SUCCEEDED` | `READY -> RUNNING` through a new attempt. | Human reviewer explicitly requests another attempt under the same validated scope. | Human rejection reference and result under review. | Result not accepted; task remains retry-eligible. |
| Human rejection closing the task | `FAILED` | `SUCCEEDED` | None on this task. | Human reviewer rejects result and closes task unsuccessfully. | Human rejection reference and result under review. | Result not accepted; task closed. |
| Human cancellation before attempt creation | `CANCELLED` | None | None on this task. | Human cancellation or cancellation policy. | Cancellation decision. | Work stopped before attempt creation. |
| Human cancellation before dispatch | `CANCELLED` | `CANCELLED` | None on this task. | Human cancellation or cancellation policy. | Cancellation decision. | Work stopped before execution. |
| Human cancellation during execution | `CANCELLED` | `CANCELLED` | None on this task. | Human cancellation or cancellation policy after best-effort executor cancellation. | Cancellation decision and partial evidence reference when available. | Work stopped; no retry on the cancelled task. |

These behaviors are contract requirements only. They have not been implemented
or benchmarked by this issue.

## Approval And Security Boundaries

The first MVP is read-only by contract.

The executor cannot:

- modify Kubernetes resources
- change rollout state
- promote, abort, retry, undo, or patch an Argo Rollout
- modify GitOps configuration
- execute remediation
- merge pull requests
- close the operational incident
- close SRE Platform issues
- start or stop controlled failure workloads
- broaden investigation scope without human approval

Recommendations require human evaluation. Final AI Operations task completion
requires an explicit human decision. Credentials, authorization model,
identity provider, secret storage, network path, runtime isolation, and
least-privilege implementation remain later architecture decisions.

If a future workflow prepares a patch, pull request, rollback, remediation,
or automated recovery action, that work is outside this MVP and requires a
separate approved workstream.

## Objective PASS/FAIL Criteria For Future Implementation

The future end-to-end MVP demonstration may PASS only when all conditions are
true:

1. the accepted staging scenario is reproducibly identified;
2. a valid normalized request creates one durable task;
3. the task creates a separately identifiable attempt;
4. required capabilities are declared and verified before dispatch;
5. a missing required capability fails closed;
6. one read-only executor is invoked through the adapter boundary;
7. the executor collects evidence from the approved SRE Platform scope;
8. the result conforms to the output schema;
9. findings reference supporting evidence;
10. limitations and unavailable evidence are explicit;
11. task and attempt transitions remain auditable;
12. duplicate input does not create uncontrolled duplicate work;
13. timeout or executor failure produces an explicit non-success outcome;
14. a durable GitHub reference is produced;
15. the workflow stops for human review;
16. no remediation or mutation occurs;
17. the environment can be restored through the SRE Platform's owned
    procedure;
18. the demonstration can be repeated with a new request, task, and attempt
    identity.

The implementation must FAIL when any mandatory condition is absent, violated,
or represented only by an unverified claim. `NOT TESTED` never means `PASS`.
Dispatch acceptance, session creation, command execution, and raw executor
output are not sufficient evidence of task completion.

## Future 5-10 Minute Demo Script

This is the intended future demonstration. It is not currently validated by
this issue.

1. Show the healthy staging baseline for `online-shop-stage` and frontend.
2. Start or identify the approved SRE-owned controlled failure against
   `/stage/break`.
3. Submit the normalized investigation request with `schema_version: "1.0"`.
4. Show durable creation of `request_id`, `task_id`, and `attempt_id`.
5. Show required capability declarations and verification results.
6. Invoke one read-only executor through the adapter.
7. Show collected Kubernetes, rollout, Prometheus, logs, and GitOps evidence.
8. Show structured findings that reference evidence IDs.
9. Publish or link the durable GitHub reference.
10. Show that the workflow stops at `AWAITING_HUMAN_REVIEW`.
11. Restore or verify restoration through the SRE Platform-owned procedure.
12. Explicitly close the AI Operations task after human review.
13. Demonstrate one fail-closed path, preferably missing
    `prometheus.query` or an unavailable executor.

The demo must distinguish the AI Operations task closeout from resolution of
the underlying operational condition.

## Implementation Handoff

Separate follow-up workstreams:

1. validate the first investigator candidate and deployment boundary against
   SRE Platform development or staging;
2. decide the minimum control-plane implementation architecture;
3. implement the thin sequential control-plane skeleton;
4. implement durable task and attempt state;
5. implement capability verification;
6. implement one replaceable read-only SRE executor adapter;
7. run the accepted end-to-end demo;
8. execute the orchestrator acceptance benchmark only after the candidate
   architecture is integrated.

Unresolved decisions intentionally left open:

- control-plane implementation technology
- persistence product and schema implementation
- transport or entry mechanism for operator-triggered requests
- transport or entry mechanism for normalized SRE Platform events
- executor framework, runtime, and model
- credentials and least-privilege authorization implementation
- evidence artifact storage location
- GitHub publication format
- timeout, retry, and stale-attempt budgets
- exact SRE Platform staging restore procedure for the demo
- whether HolmesGPT, another investigator, or a custom adapter is evaluated
  first

No control-plane, infrastructure, database, workflow engine, queue, transport,
hosting product, AI model, or investigator framework is selected by this
document.
