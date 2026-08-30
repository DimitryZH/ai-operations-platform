# HolmesGPT Investigator Validation

## Status

Issue: [#23](https://github.com/DimitryZH/ai-operations-platform/issues/23)

Validation date: 2026-08-14

Conclusion: `PROTOTYPE_REQUIRED`

This document validates HolmesGPT only as an unselected, replaceable,
read-only candidate for the first SRE investigator. It does not select
HolmesGPT, select an AI model, select a hosting mode, deploy anything, access
a cluster, access cloud resources, or modify the SRE Platform repository.
The separately scoped local HTTP adapter prototype described below does not
validate a live HolmesGPT runtime or change this conclusion.

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
For MVP use, authentication, network restriction, and TLS or equivalent
transport protection would be mandatory. The HTTP API documentation has an
important unresolved contradiction: it states that `HOLMES_API_KEY` protects
all endpoints except `/healthz` and `/readyz`, but later states that admin
reload endpoints are currently unauthenticated. The effective behavior was not
tested by this validation. Any prototype must treat admin endpoint exposure as
`NOT TESTED` until proven and must fail closed if admin reload paths are
reachable without the approved protection.

## Smallest Credible Prototype Boundary

The smallest credible prototype is a private, non-production deployment and
invocation path:

```text
AI Operations Platform control plane
-> product-neutral adapter boundary
-> private-network HolmesGPT HTTP API
-> HolmesGPT read-only toolsets
-> approved SRE Platform evidence sources
```

The prototype boundary must keep HolmesGPT behind a private network endpoint.
No public ingress is acceptable for the prototype. The adapter is the only
component that may invoke HolmesGPT, and it must call the HolmesGPT HTTP API
with one approved investigation request carrying the MVP correlation metadata,
scope, time range, capability set, read-only constraints, and response schema.

HolmesGPT must not own task or attempt lifecycle state. The adapter boundary
must own invocation correlation, timeouts, cancellation mapping, raw-output
capture, result normalization, and capability verification evidence. Private
network exposure is a prototype precondition, not a production architecture
selection.

## Capability Matrix

| MVP capability | HolmesGPT evidence | Validation result | Adapter or prototype requirement |
| --- | --- | --- | --- |
| `kubernetes.read` | Built-in Kubernetes core toolset is documented as read-only and uses in-cluster ServiceAccount or local kubeconfig permissions. Namespace-scoped access is documented through an existing ServiceAccount plus Role/RoleBinding. | Documented capability; namespace scope untested; workload-bound scope not proven. | Prototype must separately prove namespace-scoped RBAC for `online-shop-stage` and workload-bound evidence for `frontend`. A standard namespace Role can prevent cross-namespace reads, but it does not by itself guarantee that HolmesGPT reads only the `frontend` workload inside that namespace. |
| `logs.read` | Built-in Kubernetes logs toolset is enabled by default and documents pod log tools. | Documented capability; namespace, workload, pod/container, time-range, and truncation bounds untested. | Kubernetes RBAC can scope pod log access to a namespace, but a standard namespace Role does not inherently enforce `frontend`-only or time-range-only log access. Prototype must prove a bounded proxy, custom toolset, or equivalent fail-closed enforcement path for workload and time bounds. |
| `prometheus.query` | Prometheus toolset documents `prometheus/metrics`, `prometheus_url`, instant/range query tools, rule listing, and query timeout settings. | Documented capability; target endpoint untested; PromQL enforcement gap unresolved. | If the built-in HolmesGPT toolset connects directly to Prometheus, an external adapter cannot reliably restrict the PromQL generated after dispatch. Prototype must use a bounded Prometheus proxy, custom toolset, or equivalent enforcement layer; otherwise `prometheus.query` remains a fail-closed gap. |
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
- namespace-scoped RBAC and workload-bounded evidence are different controls:
  a namespace Role can restrict Kubernetes reads to `online-shop-stage`, but
  does not by itself prove that HolmesGPT cannot inspect non-`frontend`
  workloads in the same namespace.

Minimum MVP-compatible configuration would need to disable or block any
toolset that can escape the approved evidence boundary, including remediation
and uncontrolled shell or internet access, unless a prototype proves it is
strictly bounded and non-mutating for this use case.
For Prometheus and logs, prompt instructions and adapter-side result filtering
are not sufficient enforcement when HolmesGPT toolsets can query the source
directly. The accepted MVP boundary needs a bounded proxy, custom toolset, or
another enforceable mechanism before those capabilities can pass.

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
The adapter can enforce what it controls before and after invocation, but it
cannot guarantee in-tool query narrowing for a built-in HolmesGPT toolset that
talks directly to Prometheus or Kubernetes logs. Any such direct access must be
bounded below HolmesGPT, replaced by a custom toolset, or treated as a
fail-closed enforcement gap.

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
- Workload-bound evidence controls for `frontend` inside `online-shop-stage`,
  separate from namespace-level RBAC.
- Pod log source, container, time-range, and truncation controls. These cannot
  be treated as proven solely because namespace-level `pods/log` access exists.
- Prometheus endpoint reachability and query limits, preferably through a
  bounded proxy or custom toolset because adapter-side filtering cannot
  constrain direct PromQL calls made by the built-in toolset.
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
| Prototype deployment boundary | HolmesGPT is reachable only on a private network endpoint, with no public ingress, and only the adapter invokes its HTTP API. | HolmesGPT is publicly reachable, bypasses the adapter, or exposes admin paths outside the private boundary. |
| HTTP API protection | `HOLMES_API_KEY`, network policy, and admin endpoint behavior are verified, including the documented API-key/admin-reload contradiction. | Admin reload endpoints are reachable without approved protection, or effective auth behavior remains ambiguous after the prototype. |
| Capability declaration | Adapter declares exactly the six required MVP capabilities and unsupported mutation capabilities. | Any required capability is missing, ambiguous, broader than scope, or write-capable. |
| Namespace RBAC scope | Effective ServiceAccount can read approved `online-shop-stage` Kubernetes resources and cannot mutate, read secrets, or see unapproved namespaces. | Any write verb, secret access beyond approved auth, or unapproved namespace visibility is available. |
| Workload evidence scope | Evidence collection is enforceably bounded to `frontend` and related Rollout/AnalysisRun resources inside `online-shop-stage`. | Prototype relies only on a standard namespace Role, prompt instructions, or result filtering to claim `frontend`-only access. |
| Logs scope | Pod logs are enforceably bounded by namespace, workload, pod/container selection, time range, and truncation policy. | HolmesGPT can directly read arbitrary same-namespace logs, ignore time bounds, or expose unbounded log output. |
| Prometheus scope | HolmesGPT queries only approved SLO/ingress expressions for the approved time range through a bounded proxy, custom toolset, or equivalent enforcement layer. | Built-in Prometheus toolset has direct unbounded PromQL access, query enforcement is only adapter-side, or endpoint access fails. |
| GitOps evidence | Adapter retrieves Argo CD and repository refs through a documented least-privilege path. | GitOps source is unavailable, write-capable, or not attributable to the request. |
| Structured result | HolmesGPT response can be normalized into the MVP result schema, including partial-result handling. | Output is malformed, unsupported, unsafe, or cannot preserve evidence IDs. |
| Lifecycle mapping | Timeout, cancellation, executor loss, malformed output, partial result, and success map deterministically to MVP task and attempt states. | Adapter must infer ambiguous task or attempt states from HolmesGPT behavior. |

This issue did not execute that prototype. Runtime validation remains
`NOT TESTED`.

## Local HTTP Adapter Prototype

The control plane now includes a bounded, opt-in local HTTP adapter prototype
behind the product-neutral executor interface. The fake executor remains the
default. The prototype accepts a non-streaming `/api/chat` response only when
its `analysis` can be normalized into the canonical investigation-result
schema. It includes the durable task, attempt, idempotency, and fencing
identities in its bounded request and verifies those identities again before a
result is returned to the workflow.

The adapter permits only an explicit local fixture endpoint during tests. A
non-fixture configuration requires a private HTTPS hostname, but its capability
declaration fails closed because durable remote status lookup and restart-safe
idempotency were not verified. Local fixture idempotency is explicitly
`process_local`; a new adapter instance returns `STALE` for an unknown attempt
so reconciliation cannot mistake volatile state for confirmed remote state.
The adapter does not configure credentials or send an authorization header.
Capability declarations must exactly match the accepted read-only scope and
state required mutation denials. Redirects, malformed or oversized responses,
unsafe evidence references, unapproved endpoints, and ambiguous responses fail
closed. A successful response must declare a JSON-compatible `Content-Type`
before its `analysis` is parsed. The local prototype does not support
`cancel_attempt`: it fails closed and does not claim to interrupt an in-flight
HTTP call or alter a completed result.

This code is local adapter coverage only. Private deployment, effective API
authentication and admin endpoint protection, effective Kubernetes RBAC,
workload-bounded evidence, bounded Prometheus and log access, model behavior,
and a live investigation are all `NOT TESTED`. In particular, the existing
Prometheus and logs enforcement gaps still require a bounded proxy or custom
toolset before a real prototype can satisfy the MVP boundary.

## Decision

`PROTOTYPE_REQUIRED`

HolmesGPT is a credible candidate for the first read-only SRE investigator
because it documents Kubernetes, logs, Prometheus, ArgoCD, GitHub, HTTP API,
structured output, and namespace-scoped access paths. However, the accepted
MVP requires deterministic lifecycle ownership, strict capability verification,
read-only evidence boundaries, schema-valid output, retry/stale/timeout
handling, and GitHub-auditable result normalization that HolmesGPT does not
provide as an accepted contract by itself.

The decisive unresolved gaps are enforcement gaps, not just documentation
gaps: direct built-in toolset access to Prometheus or pod logs cannot be
bounded by an external adapter after dispatch, and namespace-scoped Kubernetes
RBAC does not automatically mean workload-bounded `frontend` access.

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
| Control plane or adapter implemented | PASS: bounded local HTTP adapter prototype only |
| Cluster or cloud accessed | PASS: none |
| SRE Platform modified | PASS: no changes |
| Runtime HolmesGPT behavior claimed | PASS: no runtime claim; live behavior is NOT TESTED |
| Minimum prototype outcome | NOT TESTED |
