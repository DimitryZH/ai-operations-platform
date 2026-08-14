# ADR 0002: First SRE MVP Control-Plane Architecture

## Status

Proposed for human review.

## Context

Issue #25 asks for the smallest control-plane architecture that can implement
the accepted first SRE investigation contract without implementing code,
deploying HolmesGPT, accessing a Kubernetes cluster, modifying the SRE Platform
repository, or selecting HolmesGPT as the final investigator.

The accepted direction is a bounded, read-only SRE investigation MVP for the
existing SRE Platform staging scenario:

- namespace: `online-shop-stage`
- Argo CD application: `online-shop-stage`
- workload under investigation: `frontend`
- Rollout resource: `frontend`
- ingress: `online-shop-frontend`

The current baseline reviewed for this decision is:

- `DimitryZH/ai-operations-platform` main:
  `5539d30f56c1565e98caf11fed6fe5a2606ccfd9`
- `DimitryZH/sre-platform` main:
  `aecd1adaa8ba72a5a44453e805ae2a57e5f7731a`

The accepted MVP contract requires durable external task and attempt state,
deterministic lifecycle transitions, fail-closed capability verification, one
sequential executor, restart reconciliation, schema-valid structured results,
GitHub-auditable publication, and explicit human closeout. GitHub may be an
audit and publication surface, but not the transactional database. In-memory
state and interactive sessions are not durable truth.

HolmesGPT remains `PROTOTYPE_REQUIRED`. It is a credible read-only investigator
candidate, but the accepted validation identifies unresolved enforcement gaps
around direct Prometheus access, logs bounds, workload-bounded Kubernetes
evidence, and effective HTTP API protection. This ADR does not select
HolmesGPT, an AI model, or any final executor implementation.

## Decision

Select a small Python control plane:

- implementation language: Python 3.13
- API framework: FastAPI
- request and result schema validation: Pydantic
- database access and migrations: SQLAlchemy plus Alembic
- durable persistence: PostgreSQL
- minimum GCP target: Cloud Run, Cloud SQL for PostgreSQL, Cloud Storage,
  Secret Manager, Cloud Scheduler, Cloud Logging, and Cloud Monitoring

The control plane owns lifecycle state. The executor remains replaceable behind
a product-neutral adapter interface. LLM behavior, if any, is confined to the
executor side of that adapter and does not own task state, retry decisions,
capability acceptance, GitHub publication, or human closeout.

## Architecture

The first deployable architecture is:

```text
Operator or event source
  -> FastAPI ingestion endpoint
  -> PostgreSQL transactional state machine
  -> DB-locked sequential dispatcher
  -> product-neutral executor adapter
  -> read-only investigator candidate
  -> normalized result validation
  -> Cloud Storage evidence references
  -> GitHub publication
  -> human review and closeout endpoint
```

PostgreSQL is the only transactional source of truth. The service may publish
comments, links, or summaries to GitHub, but GitHub comment state must never be
used to infer task state after restart.

Cloud Scheduler only triggers protected reconciliation and dispatch ticks. It
does not own workflow state and is not a queue. If a scheduled tick is missed,
the next tick must reconcile from PostgreSQL before dispatching new work.

## Transaction Boundary

Every lifecycle transition is recorded in a PostgreSQL transaction. External
calls are not made while relying on uncommitted state. Before an external call,
the control plane persists an invocation intent with an idempotency key. After
the call returns or times out, the control plane records the normalized outcome
in a new transaction.

Minimum durable tables are:

- `requests`
- `tasks`
- `attempts`
- `task_transitions`
- `attempt_transitions`
- `capability_checks`
- `executor_invocations`
- `evidence_artifacts`
- `github_publications`
- `human_reviews`
- `control_locks`

The transaction boundary for state changes is one task, its current attempt,
and related transition, capability, invocation, evidence, publication, or
review records. Cross-task transactions are not required for the first MVP.

## Request Ingestion

FastAPI accepts the first SRE investigation request through a versioned HTTP
endpoint such as `POST /v1/sre-investigations`.

Pydantic validates:

- schema version
- request identifier or idempotency key
- approved scenario fields
- target namespace, workload, rollout, ingress, and time range
- read-only constraints
- GitHub publication target
- evidence policy

Invalid input is rejected before activation and records no attempt.

Duplicate handling is deterministic:

- the same request id and same payload return the existing task reference
- the same request id with a different payload is rejected
- a repeated operational event fingerprint attaches an audit reference to the
  existing task and creates no new attempt
- unique database constraints enforce idempotency independently of application
  process lifetime

## Lifecycle Ownership

The control plane is the only component allowed to transition task and attempt
state. The adapter reports capabilities, dispatch acceptance, status, result,
or error details; it does not directly set durable lifecycle state.

Task and attempt states follow the accepted MVP contract. In particular:

- a terminal task state never creates another attempt
- retry on the same task is allowed only while the task is in a retry-eligible
  non-terminal state such as `READY`
- every retry creates a new `attempt_id`
- `STALE` is terminal for the affected attempt, and the parent task is
  reconciled separately
- a schema-valid partial result makes the attempt `SUCCEEDED` and moves the
  parent task to `AWAITING_HUMAN_REVIEW`
- malformed output, missing required fields, adapter failure, timeout, stale
  executor state, and capability rejection use deterministic non-success
  states from the MVP contract

The dispatcher owns the transition from `READY` to `RUNNING` and the creation
of a new attempt. Human reviewers own explicit closeout transitions from
`AWAITING_HUMAN_REVIEW` to `COMPLETED`, `READY`, `FAILED`, or `CANCELLED`
according to the accepted contract.

## Sequential Dispatch And Restart Reconciliation

The first MVP uses a database-backed single dispatcher. The dispatcher obtains
a PostgreSQL lock before selecting one eligible `READY` task. Cloud Run
`max-instances` may be set to one for operational simplicity, but correctness
depends on the database lock, not on process uniqueness.

Dispatch order is deterministic:

1. reconcile unfinished attempts
2. expire task or attempt budgets
3. select the oldest eligible `READY` task
4. create a new attempt
5. verify capabilities fail-closed
6. persist dispatch intent
7. call the adapter with the attempt idempotency key
8. persist the normalized adapter outcome

Restart reconciliation must run before new dispatch. It must inspect durable
attempt records, last heartbeat or status timestamps, invocation intents, and
adapter-observable state. If the active executor cannot be observed safely, the
attempt becomes terminal `STALE`. The parent task returns to `READY` only when
retry is still allowed; otherwise it transitions to terminal `FAILED` or
`TIMED_OUT` according to the recorded budget and failure reason.

## Capability Verification

Capability verification is fail-closed and occurs before dispatching an active
investigation.

The control plane verifies that the adapter can satisfy exactly the required
MVP capabilities within the approved scope:

- `kubernetes.read`
- `prometheus.query`
- `rollout.read`
- `gitops.read`
- `logs.read`
- `investigation.report`

The adapter must also declare unsupported mutation capabilities, including
Kubernetes writes, rollout mutation, GitOps writes, deployment writes,
remediation, pull request merge, incident closeout, and secret reads beyond the
minimum approved authentication path.

Capability verification rejects prompt-only, result-filter-only, or
post-dispatch-only enforcement. If an investigator has direct access to
Prometheus or pod logs, the control plane requires a bounded proxy, custom
toolset, or equivalent enforcement layer before accepting that capability.
Namespace-scoped Kubernetes RBAC and workload-bounded evidence for `frontend`
are separate checks.

## Executor Adapter Interface

The executor adapter is product-neutral. The initial control-plane code should
define the interface before selecting a concrete investigator implementation.

Minimum operations are:

| Operation | Purpose |
| --- | --- |
| `describe_capabilities` | Return executor identity, schema versions, declared capabilities, denied capabilities, target scope, auth mode, and verification evidence. |
| `start_investigation` | Start one read-only attempt using `request_id`, `task_id`, `attempt_id`, approved scope, time range, constraints, evidence policy, and idempotency key. |
| `get_status` | Report accepted, queued, running, succeeded, failed, timed out, stale, or cancelled without mutating control-plane state directly. |
| `get_result` | Return a schema-valid normalized result, including `status: partial` when evidence is incomplete but reviewable. |
| `cancel_attempt` | Request bounded cancellation and return whether partial evidence exists. |

The first implementation increment should include a fake adapter for lifecycle
and contract tests. HolmesGPT, another investigator, or a custom adapter can be
evaluated later without changing the control-plane state machine.

## Local Development And Tests

Local development uses:

- Python virtual environment
- FastAPI development server
- Docker Compose PostgreSQL
- Alembic migrations
- pytest unit and integration tests
- fake executor adapter
- local filesystem or fake object-store evidence adapter for tests

Local tests must not require a Kubernetes cluster, cloud resources, HolmesGPT,
or the SRE Platform repository to be mutable. SRE Platform references are test
fixtures and documentation inputs only until a separate runtime validation
issue authorizes prototype access.

Minimum test coverage for the first implementation increment should include:

- schema validation
- duplicate request handling
- task and attempt transition ownership
- retry and terminal-state behavior
- stale attempt reconciliation
- dispatcher lock behavior
- capability rejection
- partial-result handling
- GitHub publication idempotency using a fake publisher

## Minimum GCP Deployment Target

The minimum GCP deployment target is:

- Cloud Run service for the FastAPI control plane, with authenticated private
  access and no public unauthenticated ingress
- Cloud SQL for PostgreSQL as durable transactional state
- Cloud Storage bucket for sanitized evidence artifacts
- Secret Manager for database, GitHub, adapter, and future executor secrets
- Cloud Scheduler with IAM-authenticated calls to protected reconciliation and
  dispatch endpoints
- Cloud Logging for structured logs
- Cloud Monitoring for health, readiness, metrics, and alerting

This target does not require GKE for the control plane and does not deploy an
investigator. A future HolmesGPT prototype, if approved, must remain behind a
private network endpoint with no public ingress.

## Evidence Storage And GitHub Publication

Evidence artifacts are stored outside GitHub in Cloud Storage or the local test
evidence adapter. The database stores artifact URI, hash, content type,
sanitization status, producing attempt, and retention metadata.

GitHub publication is an audited side effect:

- publication uses a GitHub App or least-privilege token
- each publication stores an idempotency key and resulting GitHub reference
- retrying publication must update or reuse the existing reference rather than
  creating ambiguous duplicates
- publication failure does not rewrite investigation results
- GitHub is not the transactional source of truth

Published summaries must preserve evidence references, limitations, partial
status, and human-review instructions without exposing large raw logs or
secrets.

## Human Review And Closeout

The first MVP does not need a custom UI. Human review can use a GitHub comment
or pull request conversation plus a protected control-plane endpoint or CLI
command that records the closeout decision in PostgreSQL.

Allowed human decisions are:

- accept the reviewable result and close the task as `COMPLETED`
- reject the result and request another attempt under the same validated scope,
  returning the task to `READY`
- reject the result and close the task as `FAILED`
- cancel the task as `CANCELLED`

The human decision record must include actor, timestamp, task id, reviewed
attempt id, GitHub reference, decision, rationale, and resulting transition.

## Observability And Health

Minimum endpoints are:

- `GET /healthz` for process liveness
- `GET /readyz` for database connectivity and migration readiness
- `GET /metrics` for operational counters and latency histograms

Minimum telemetry includes:

- request, task, attempt, and transition counts by state
- dispatcher lock acquisition and skipped dispatch counts
- capability check pass and fail counts
- stale, timeout, retry, cancellation, and terminal closeout counts
- GitHub publication success and failure counts
- evidence artifact write failures
- adapter call duration, timeout, and normalized error category

Every log line should include request id, task id, attempt id when available,
executor id when available, and GitHub reference when available.

## Security

The selected architecture preserves least privilege:

- Cloud Run requires authenticated invocation
- internal endpoints require IAM and are not public
- database credentials and tokens are stored in Secret Manager
- the control-plane service account receives only required Cloud SQL, Cloud
  Storage, Secret Manager, logging, and monitoring permissions
- GitHub credentials are scoped to the required repository operations
- evidence artifacts are sanitized before publication
- capability verification fails closed before dispatch
- executor credentials are isolated behind the adapter boundary

No component in this ADR is allowed to mutate Kubernetes resources, rollout
state, GitOps configuration, deployments, incidents, or pull request merge
state for the first SRE MVP.

## Options Considered

### Option 1: Python FastAPI, PostgreSQL, And Cloud Run

This is the selected option.

It is the smallest credible architecture because FastAPI and Pydantic provide a
small typed HTTP boundary, PostgreSQL provides durable transactions and locks,
and Cloud Run plus Cloud SQL is enough to operate the control plane without
introducing a workflow engine, message broker, or Kubernetes-hosted control
plane. The product-neutral adapter keeps the investigator replaceable.

### Option 2: TypeScript API, PostgreSQL, And Cloud Run

This is credible, but not selected.

It can satisfy the same state-machine and deployment requirements, but it does
not reduce the first MVP surface. It would introduce another application
runtime without a clear advantage for the accepted contract, and the control
plane still needs the same PostgreSQL transactions, dispatcher lock, adapter
contract, evidence store, and GitHub publication logic.

### Option 3: Temporal Or Cloud Workflows With Worker Services

This is credible for larger workflow orchestration, but not selected for the
first MVP.

It adds a workflow runtime and operational concepts before the platform has
proved the single sequential executor and deterministic lifecycle. The accepted
contract can be implemented with PostgreSQL state and a DB-locked dispatcher.
Workflow orchestration can be revisited after the first MVP demonstrates that a
single deterministic control plane is insufficient.

## Consequences

Positive consequences:

- durable lifecycle truth is explicit and transactional
- retry, timeout, stale, duplicate, and human-review behavior are deterministic
- executor replacement remains a core property
- capability verification can fail closed before work begins
- the first GCP target is small and managed
- local tests can run without cluster or cloud access
- HolmesGPT remains a future prototype candidate rather than a selected
  dependency

Costs and tradeoffs:

- a new Python service and PostgreSQL schema must be implemented
- Cloud SQL becomes a required dependency for the deployed control plane
- Cloud Scheduler adds a managed tick mechanism, even though it owns no state
- a custom state-machine test suite is required
- future workflow-engine adoption would require a separate ADR or decision

## Follow-Up Increments

1. Scaffold the FastAPI service, PostgreSQL schema, migrations, and fake
   executor adapter.
2. Implement request ingestion, schema validation, idempotency, task and
   attempt transitions, and transition tests.
3. Implement DB-locked sequential dispatch, retry budgets, timeout handling,
   and stale-attempt reconciliation.
4. Implement fail-closed capability verification and adapter contract tests.
5. Implement evidence artifact storage, GitHub publication idempotency, and
   human closeout recording.
6. Define minimal GCP infrastructure for Cloud Run, Cloud SQL, Cloud Storage,
   Secret Manager, Cloud Scheduler, logging, and monitoring.
7. Run a separate human-reviewed HolmesGPT or alternative-investigator prototype
   only after the bounded capability enforcement plan is accepted.

## Ownership Boundaries

AI Operations Platform owns:

- control-plane implementation
- PostgreSQL schema and lifecycle state machine
- adapter contract
- fake adapter and control-plane tests
- evidence storage integration
- GitHub publication and human closeout
- future investigator prototype orchestration

SRE Platform owns:

- the stage scenario application and GitOps configuration
- workload, rollout, ingress, Prometheus, log, and recovery source ownership
- any future SRE Platform repository changes required for a prototype
- restoration or operational incident procedures

This ADR changes no SRE Platform files and authorizes no cluster or cloud
access.

## Revisit Criteria

Revisit this decision if:

- one sequential executor is insufficient after implementation evidence
- PostgreSQL locking cannot provide acceptable dispatch and reconciliation
  behavior
- Cloud Run request or scheduling constraints block the MVP workflow
- evidence storage or GitHub publication requirements require a different
  deployment model
- a future prototype proves that a selected investigator requires a different
  adapter or hosting boundary

## References

- Issue #25:
  https://github.com/DimitryZH/ai-operations-platform/issues/25
- Roadmap:
  `docs/roadmap.md`
- First SRE investigation MVP contract:
  `docs/mvp/first-sre-investigation.md`
- HolmesGPT investigator validation:
  `docs/integrations/sre/holmesgpt-investigator-validation.md`
- ADR 0001:
  `docs/adr/0001-primary-orchestrator-foundation.md`
- SRE Platform repository:
  https://github.com/DimitryZH/sre-platform
