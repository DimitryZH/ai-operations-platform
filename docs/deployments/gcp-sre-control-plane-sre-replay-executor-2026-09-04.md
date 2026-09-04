# GCP SRE Control-Plane SRE Replay Executor Evidence - 2026-09-04

This document records sanitized evidence for Issue #55. It intentionally omits
account emails, service-account emails, principal IDs, credentials, token
values, database URLs, Terraform state, Terraform plan files, raw logs, raw
cluster output, endpoint data, and private operator notes.

## Scope

- GitHub issue: #55
- Repository branch: `codex/issue-55-sre-readonly-executor`
- Target project context: `ai-operations-platform-507220`
- Target region context: `us-central1`
- Runtime executor default: fake executor
- New executor mode: `sre_replay`, explicit opt-in only
- Runtime evidence store boundary: existing GCS evidence adapter remains
  enabled in reviewed private runtime configuration
- Runtime publisher boundary: GitHub publisher remains opt-in and allowlisted
- Cloud Run boundary: private internal ingress with authenticated invocation
- Scheduler boundary: remains `PAUSED`
- Integration boundary: no SRE Platform repository mutation and no cluster
  access

## Read-Only Preflight

Read-only checks before implementation confirmed:

- `main` was updated before the Issue #55 branch was created.
- Issue #55 was open and requested a bounded read-only SRE investigation
  executor adapter.
- The existing executor interface supports capability declaration,
  idempotent start, status lookup, result retrieval, and cancellation.
- The dispatcher records durable capability and invocation intent before
  invoking the executor, and external executor calls happen outside database
  transactions and locks.
- The private GCP runtime foundation already keeps Cloud Run internal and
  authenticated, Scheduler paused, GCS evidence enabled, GitHub publisher
  opt-in and allowlisted, and fake executor default.
- The SRE Platform repository was inspected only as read-only local context.
  It was not modified, deployed, or executed.

## SRE Platform Replay Contract Context

Sanitized repository context used for the replay contract:

- SRE Platform branch inspected: `main`.
- SRE Platform commit inspected: `aecd1ad`.
- Approved logical cluster identifier: `sre-platform-staging`.
- Approved namespace: `online-shop-stage`.
- Approved workload and rollout: `frontend`.
- Approved GitOps application: `online-shop-stage`.
- Approved path prefix: `/stage`.
- Approved controlled failure path: `/stage/break`.
- Approved SLO query names: `slo:error_ratio_5m`,
  `slo:burn_rate_5m`, and `stage_ingress_request_rate_5m`.
- Approved GitOps read paths are limited to the stage application, stage
  values overlay, and frontend/break/SLO chart templates.

These facts come from repository files only. They do not prove live staging
sync, current cluster state, live Prometheus values, recovery, or production
behavior.

## Implemented Boundary

- Added the `sre_replay` executor behind the existing product-neutral executor
  interface.
- Kept fake executor as the default for local development, tests, and private
  runtime unless explicitly configured otherwise.
- Runtime opt-in requires:
  - `SRE_CONTROL_PLANE_EXECUTOR=sre_replay`
  - `SRE_CONTROL_PLANE_SRE_REPLAY_SCENARIO_ID=approved-stage-frontend-slo-v1`
  - exact approved `SRE_CONTROL_PLANE_SRE_REPLAY_PROVIDERS_JSON`
- Capability verification fails closed for missing, malformed, unsafe,
  broader-than-approved, or write-capable declarations.
- Kubernetes provider declarations are restricted to the approved staging
  namespace, expected read resources, and `get`/`list` verbs.
- Prometheus provider declarations are restricted to the exact approved query
  allowlist.
- GitOps provider declarations are restricted to `DimitryZH/sre-platform`,
  `main`, approved paths, and `read_file`.
- Recovery observation is optional, read-only, and cannot claim live recovery.
- The deterministic result includes findings, evidence references,
  limitations, recommendations, approved read-only scope, and explicit
  fixture-only limitations.
- Result evidence references use bounded `sre-platform://replay/...`
  identifiers and avoid raw object contents, cluster dumps, endpoints, or
  credentials.
- Evidence packaging and publication continue through the existing workflow
  path, so PostgreSQL remains the source of truth and external evidence or
  publication calls remain outside database transactions and locks.

## Validation

Local validation performed:

- Targeted SRE replay/config/deployment test run passed.
- Unit tests cover capability declarations, namespace restrictions, write
  verbs/actions, wildcard scope, Prometheus query allowlist, GitOps scope,
  optional recovery observation, deterministic identity, schema-valid results,
  and sanitized fixture output.
- Configuration tests cover fake executor default, explicit `sre_replay`
  opt-in, incomplete config failure, unsafe config sanitization, and ambiguous
  executor config rejection.
- PostgreSQL integration tests cover task through attempt, schema-valid replay
  result, evidence package, publication reference, and unlocked external
  adapter invocation.
- Deployment regression tests cover fake runtime default, explicit Terraform
  opt-in for `sre_replay`, embedded sanitized provider declarations, private
  Cloud Run boundary, paused Scheduler, GCS evidence boundary, GitHub publisher
  boundary, and absence of tracked secret values.

Additional validation results are recorded in the pull request description.

## Non-Events

- No GCP runtime image was pushed.
- No Terraform plan was created.
- No Terraform apply was executed.
- No Secret Manager version was created or changed.
- No live Kubernetes, Prometheus, Argo CD, recovery, HolmesGPT, or model call
  was made.
- No SRE Platform repository file was modified.
- No Scheduler activation occurred.
- No GitHub publication smoke comment was written for this issue.
- No merge was performed and Issue #55 was not closed.
