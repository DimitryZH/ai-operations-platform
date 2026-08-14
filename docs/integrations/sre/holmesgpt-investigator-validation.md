# HolmesGPT Investigator Validation

## Status

Issue: [#23](https://github.com/DimitryZH/ai-operations-platform/issues/23)

Validation date: 2026-08-14

Conclusion: `PROTOTYPE_REQUIRED`

This document validates HolmesGPT only as an unselected, replaceable,
read-only candidate for the first SRE investigator. It does not select
HolmesGPT, select an AI model, select a hosting mode, implement a control
plane, implement an adapter, deploy anything, access a cluster, access cloud
resources, or modify the SRE Platform repository.

## Repository Baseline

| Repository | Branch | Commit | Inspection mode |
| --- | --- | --- | --- |
| `DimitryZH/ai-operations-platform` | `main` | `e3ad471c25818ebe7a8fd86931ee58c7edae39df` | Accepted MVP contract and platform docs only |
| `DimitryZH/sre-platform` | `main` | `aecd1adaa8ba72a5a44453e805ae2a57e5f7731a` | Repository files only; no changes, deploys, or runtime checks |
| `HolmesGPT/holmesgpt` | `master` | `1789e968b2e4439f0cf9e6a378c8edf3eb11c078` | Shallow source/doc inspection only |

Current HolmesGPT release state inspected from GitHub:

- Latest release: [`0.39.0`](https://github.com/HolmesGPT/holmesgpt/releases/tag/0.39.0)
- Release commit shown by GitHub: `3606c7e`
- Release date shown by GitHub: 2026-08-10
- Current inspected `master` commit is newer than the latest release.

Primary AI Operations Platform sources:

- [First SRE Investigation MVP Contract](../../mvp/first-sre-investigation.md)
- [Roadmap](../../roadmap.md)
- [ADR 0001: Primary Orchestrator Foundation](../../adr/0001-primary-orchestrator-foundation.md)
- [Orchestrator Acceptance Benchmark](../../benchmarks/orchestrator-acceptance-benchmark.md)

Primary HolmesGPT sources:

- [README](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/README.md)
- [HTTP API reference](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/reference/http-api.md)
- [Kubernetes installation](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/installation/kubernetes-installation.md)
- [Namespace-scoped access](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/installation/namespace-scoped-access.md)
- [Kubernetes toolset](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/data-sources/builtin-toolsets/kubernetes.md)
- [Prometheus toolset](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/data-sources/builtin-toolsets/prometheus.md)
- [ArgoCD toolset](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/data-sources/builtin-toolsets/argocd.md)
- [GitHub MCP toolset](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/data-sources/builtin-toolsets/github-mcp.md)
- [Kubernetes Remediation MCP toolset](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/data-sources/builtin-toolsets/kubernetes-remediation-mcp.md)
- [Kubernetes MCP toolset](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/docs/data-sources/builtin-toolsets/kubernetes-mcp.md)
- [Helm values](https://github.com/HolmesGPT/holmesgpt/blob/1789e968b2e4439f0cf9e6a378c8edf3eb11c078/helm/holmes/values.yaml)

## Accepted MVP Boundary

The accepted MVP contract requires a sequential, read-only, GitHub-auditable,
replaceable executor boundary. The control plane owns durable request, task,
attempt, capability, evidence, result, retry, stale-attempt, timeout, and
human-review state. The executor may collect only approved read-only evidence
through an adapter.

The verified SRE Platform scenario remains unchanged:

- namespace: `online-shop-stage`
- Argo CD application: `online-shop-stage`
- workload under investigation: `frontend`
- Rollout resource: `frontend`
- ingress: `online-shop-frontend`
- stage path prefix: `/stage`
- controlled failure path: `/stage/break`
- SLO analysis template: `frontend-slo-check`
- Prometheus signals: `slo:error_ratio_5m` and `slo:burn_rate_5m`
- Prometheus endpoint from repository manifests:
  `http://monitoring-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090`

The SRE Platform repository inspection confirmed the Argo CD Application,
stage values, frontend Rollout canary steps, AnalysisTemplate, ingress,
controlled 500 backend, and Prometheus rules exist in repository files. No
cluster behavior was tested.

## HolmesGPT Interface Fit

HolmesGPT provides several documented invocation and deployment modes:

| Mode | Evidence | MVP fit |
| --- | --- | --- |
| CLI or UI/TUI | Documented as the common user path | Useful for manual investigation only; not sufficient for durable external task lifecycle |
| Helm service with HTTP API | Kubernetes install doc says Helm deploys HolmesGPT as a service with an HTTP API for custom integrations | Best candidate interface for an adapter prototype, but still needs external lifecycle ownership |
| `/api/chat` HTTP endpoint | HTTP API accepts `ask`, `model`, `response_format`, `stream`, `enable_tool_approval`, prompt controls, and conversation history | Can dispatch one bounded investigation request; adapter must own correlation, timeout, schema parsing, and persistence |
| SSE streaming | HTTP API emits tool start/result, approval, token, and answer-end events | Can provide progress evidence, but is not a durable attempt-state API |
| Operator mode | HolmesGPT can run background health checks | Out of scope for the accepted first MVP because the MVP entry path is bounded and externally orchestrated |
| MCP add-ons | Kubernetes, remediation, GitHub, cloud, and other add-ons are documented | Must be tightly allowlisted; remediation/write add-ons are out of scope |

HTTP API authentication is optional unless `HOLMES_API_KEY` is configured.
For MVP use, authentication, network restriction, and TLS or equivalent ingress
controls would be mandatory. The HTTP API also documents currently
unauthenticated admin reload endpoints, so any prototype must restrict admin
paths at the network boundary.

## Capability Matrix

| MVP capability | HolmesGPT evidence | Validation result | Adapter or prototype requirement |
| --- | --- | --- | --- |
| `kubernetes.read` | Built-in Kubernetes core toolset is documented as read-only and uses in-cluster ServiceAccount or local kubeconfig permissions. Namespace-scoped access is documented through an existing ServiceAccount plus Role/RoleBinding. | Documented capability; exact scope untested. | Prototype must prove the effective ServiceAccount can read only approved `online-shop-stage` resources and cannot mutate, read secrets, or see unapproved namespaces. |
| `logs.read` | Built-in Kubernetes logs toolset is enabled by default and documents pod log tools. | Documented capability; bounds untested. | Adapter must bind namespace, workload, time range, pod/container selection, and truncation policy. |
| `prometheus.query` | Prometheus toolset documents `prometheus/metrics`, `prometheus_url`, instant/range query tools, rule listing, and query timeout settings. | Documented capability; target endpoint untested. | Adapter must restrict queries to approved expressions/time windows and prove network access to the SRE Prometheus endpoint in a prototype. |
| `rollout.read` | Kubernetes CRD read permissions can include Argo-related resources; ArgoCD toolset can read application resources/manifests/history. | Partially documented; exact Argo Rollouts and AnalysisRun read behavior untested. | Prototype must prove Rollout `frontend` and related AnalysisRuns in `online-shop-stage` can be read without write verbs. |
| `gitops.read` | ArgoCD toolset documents application status, manifests, resources, diffs, history, repositories, projects, and clusters. GitHub MCP docs state read permissions are sufficient for read-only investigations. | Documented in general; SRE-specific GitOps path untested. | Adapter must decide whether GitOps evidence comes from Argo CD, GitHub, repository metadata supplied by the control plane, or a combination, then verify least privilege. |
| `investigation.report` | HTTP API supports `response_format` with strict JSON schema and returns structured content inside the `analysis` field. | Plausible but not accepted without prototype. | Adapter must parse, sanitize, normalize, validate against the MVP result schema, persist evidence references, and distinguish `succeeded`, `partial`, and `failed`. |

Result: HolmesGPT has enough documented surface area to justify a safe
prototype, but not enough verified behavior to mark the candidate suitable.

## Read-Only Boundary

The built-in Kubernetes toolset is documented as read-only. The Kubernetes
Remediation MCP toolset is explicitly out of scope because it can perform
cluster actions such as restart, scale, drain, patch, edit, diagnostic pod
creation, and container file/process access. The optional Kubernetes MCP
toolset documents `readOnly: true`, but it is also an alternate access path
that would require separate allowlisting and prototype validation.

The inspected Helm defaults require care:

- `kubernetes/core`, `kubernetes/logs`, `prometheus/metrics`, `internet`, and
  `bash` are enabled in `helm/holmes/values.yaml`.
- `modelList` is empty by default and must be provided with an approved model
  configuration.
- common MCP add-ons are configurable separately.
- namespace-scoped access is documented, but effective RBAC must be verified
  against the deployed ServiceAccount.

Minimum MVP-compatible configuration would need to disable or block any
toolset that can escape the approved evidence boundary, including remediation
and uncontrolled shell or internet access, unless a prototype proves it is
strictly bounded and non-mutating for this use case.

## Adapter Boundary

HolmesGPT should not own the MVP task lifecycle. A product-neutral adapter
would still be required for:

- `describe_capabilities`: declare configured toolsets, model/schema support,
  RBAC evidence, network reachability checks, unsupported operations, and
  explicit write-denial evidence.
- `start_investigation`: create one HolmesGPT request from the approved
  `request_id`, `task_id`, `attempt_id`, scope, time range, capabilities, and
  constraints.
- `get_status`: map HTTP/SSE progress to deterministic attempt states without
  treating HolmesGPT chat progress as durable state.
- `get_result`: parse the `analysis` response, validate schema, preserve
  evidence references, sanitize raw output, and emit the MVP result contract.
- `cancel_attempt`: apply client-side cancellation or timeout, stop consuming
  results where possible, and mark the attempt `CANCELLED`, `TIMED_OUT`, or
  `STALE` according to the control-plane contract.

No durable async job API, native MVP attempt IDs, task terminal-state policy,
or cancellation endpoint was verified in HolmesGPT. Those responsibilities
must remain in the AI Operations Platform control plane and adapter.

## Lifecycle And Result Policy Fit

The accepted MVP lifecycle can be preserved if HolmesGPT is treated only as an
executor behind the adapter:

- a terminal task state must not create another attempt;
- any retry on the same task requires the parent task to be non-terminal and a
  new `attempt_id`;
- stale HolmesGPT HTTP/SSE continuity must become terminal attempt `STALE`,
  followed by control-plane reconciliation;
- malformed, missing, or non-normalizable HolmesGPT output becomes attempt
  `FAILED`;
- a schema-valid partial report can become attempt `SUCCEEDED` with parent task
  `AWAITING_HUMAN_REVIEW`;
- adapter or executor failure without a schema-valid result is not partial
  investigation success.

HolmesGPT documentation does not by itself prove deterministic task or attempt
lifecycle consistency. The adapter must enforce it.

## Data, Secret, And Network Requirements

A prototype would need explicit least-privilege handling for:

- Kubernetes ServiceAccount token, RBAC, namespace, and CRD access.
- Prometheus endpoint reachability and query limits.
- Argo CD token or in-cluster access path if the ArgoCD toolset is used.
- GitHub token or GitHub App credentials if repository-level GitOps evidence
  is read through GitHub MCP.
- AI provider credentials in `modelList`; no provider or model is selected by
  this validation.
- Network egress only to approved Kubernetes, Prometheus, Argo CD, GitHub if
  used, and model-provider endpoints.
- Sanitization of tool output, logs, raw model output, and follow-up actions
  before GitHub publication.

## Minimum Safe Prototype

The minimum prototype should be run only after human approval in a non-production
environment and should remain bounded to the accepted SRE scenario.

Required prototype gates:

| Gate | PASS condition | FAIL condition |
| --- | --- | --- |
| Capability declaration | Adapter declares exactly the six required MVP capabilities and unsupported mutation capabilities. | Any required capability is missing, ambiguous, broader than scope, or write-capable. |
| RBAC scope | Effective ServiceAccount can read approved `online-shop-stage` resources, pod logs, Argo Rollouts/AnalysisRuns, and cannot mutate or read secrets. | Any write verb, secret access beyond approved auth, or unapproved namespace visibility is available. |
| Prometheus scope | HolmesGPT can query only approved SLO/ingress expressions for the approved time range. | Query surface is unbounded or endpoint access fails. |
| GitOps evidence | Adapter retrieves Argo CD and repository refs through a documented least-privilege path. | GitOps source is unavailable, write-capable, or not attributable to the request. |
| Structured result | HolmesGPT response can be normalized into the MVP result schema, including partial-result handling. | Output is malformed, unsupported, unsafe, or cannot preserve evidence IDs. |
| Lifecycle mapping | Timeout, cancellation, executor loss, malformed output, partial result, and success map deterministically to MVP task and attempt states. | Adapter must infer ambiguous task or attempt states from HolmesGPT behavior. |

This issue did not execute that prototype. Runtime validation remains
`NOT TESTED`.

## Decision

`PROTOTYPE_REQUIRED`

HolmesGPT is a credible candidate for the first read-only SRE investigator
because it documents Kubernetes, logs, Prometheus, ArgoCD, GitHub, HTTP API,
structured output, and namespace-scoped access paths. However, the accepted
MVP requires deterministic lifecycle ownership, strict capability verification,
read-only evidence boundaries, schema-valid output, retry/stale/timeout
handling, and GitHub-auditable result normalization that HolmesGPT does not
provide as an accepted contract by itself.

HolmesGPT remains unselected until a human-reviewed prototype proves the
adapter can enforce the accepted MVP contract without expanding scope or
granting mutation capability.

## Validation Summary

| Check | Result |
| --- | --- |
| Accepted MVP scenario changed | PASS: unchanged |
| Input or output scope changed | PASS: unchanged |
| Read-only boundary preserved | PASS: preserved as validation requirement |
| HolmesGPT selected | PASS: not selected |
| Technology selection made | PASS: none |
| Control plane or adapter implemented | PASS: none |
| Cluster or cloud accessed | PASS: none |
| SRE Platform modified | PASS: no changes |
| Runtime HolmesGPT behavior claimed | PASS: no runtime claim |
| Minimum prototype outcome | NOT TESTED |
