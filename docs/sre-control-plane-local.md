# Local SRE Control-Plane Skeleton

This document describes the first locally runnable skeleton for the accepted
SRE investigation MVP contract. It does not connect to HolmesGPT, Kubernetes,
Prometheus, cloud resources, or the SRE Platform runtime.

## Scope

Included:

- Python 3.13 FastAPI application
- Pydantic request and result models for schema version `1.0`
- SQLAlchemy table metadata matching the first durable control-plane boundary
- Alembic migration for a fresh local PostgreSQL database
- product-neutral executor interface
- deterministic fake executor for tests and local development
- an opt-in bounded SRE replay executor that validates the approved staging
  read-only provider contract from sanitized fixtures
- a database-backed sequential dispatcher with a durable global lease and
  monotonic fencing token
- one bounded local fake-executor workflow from dispatcher tick to human review
- explicit operator-controlled retry that queues retry-eligible local fake tasks
- a deterministic sanitized JSON evidence package through a bounded local filesystem adapter
- durable evidence metadata and local fake-publication audit history
- an opt-in, single-target GitHub Issue publication adapter behind the
  product-neutral publisher interface
- liveness and readiness endpoints

Excluded:

- live investigator, live HolmesGPT, or model integration
- automatic retry, timeout, and cancellation workflows
- Kubernetes, cloud resources, deployment, or SRE Platform repository changes

## Local Run

Create a Python environment and install the project:

```powershell
python -m venv .venv
. .\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
```

Start local PostgreSQL:

```powershell
docker compose up -d postgres
```

Initialize the database:

```powershell
$env:DATABASE_URL = "postgresql+psycopg://sre_control_plane:sre_control_plane@localhost:5432/sre_control_plane"
alembic upgrade head
```

Start the API:

```powershell
uvicorn sre_control_plane.app:app --reload
```

Check endpoints:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/healthz
Invoke-RestMethod http://127.0.0.1:8000/readyz
Invoke-RestMethod http://127.0.0.1:8000/v1/executors/fake/capabilities
```

Validate the canonical request:

```powershell
Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -InFile .\examples\sre-investigation-request.json `
  http://127.0.0.1:8000/v1/sre-investigations/validate
```

Queue one deterministic fake investigation:

```powershell
$task = Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -InFile .\examples\sre-investigation-request.json `
  http://127.0.0.1:8000/v1/sre-investigations

$task.task_state
```

The accepted task is persisted in `READY`; intake does not create an attempt,
verify capabilities, or invoke an executor.

Run one bounded dispatcher tick:

```powershell
$tick = Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -Body '{"lease_owner":"local-tick-001"}' `
  http://127.0.0.1:8000/internal/dispatch/tick

$tick
```

The expected task state after the successful fake execution is
`AWAITING_HUMAN_REVIEW`.

Inspect task state:

```powershell
Invoke-RestMethod "http://127.0.0.1:8000/v1/sre-investigations/$($task.task_id)"
```

Record an explicit human decision:

```powershell
Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -Body '{"decision":"complete","actor":"local-operator","rationale":"Accepted fake investigation result for local workflow validation."}' `
  "http://127.0.0.1:8000/v1/sre-investigations/$($task.task_id)/human-review"
```

Request another investigation attempt from human review:

```powershell
Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -Body '{"decision":"retry","retry_id":"retry-local-human-001","actor":"local-operator","rationale":"Request another bounded fake investigation attempt."}' `
  "http://127.0.0.1:8000/v1/sre-investigations/$($task.task_id)/human-review"
```

The retry decision returns the task to `READY`; run another dispatcher tick to
create and execute its new attempt.

Retry an eligible task that has returned to `READY` after a failed attempt:

```powershell
Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -Body '{"retry_id":"retry-local-operator-001","actor":"local-operator","rationale":"Retry after the previous terminal non-success attempt."}' `
  "http://127.0.0.1:8000/v1/sre-investigations/$($task.task_id)/retry"
```

This operator retry only records a durable decision while the task remains
`READY`; it also requires a subsequent dispatcher tick.

Run tests:

```powershell
python -m pytest
```

Run the PostgreSQL dispatcher integration tests against an explicitly selected
local database:

```powershell
$env:SRE_CONTROL_PLANE_TEST_DATABASE_URL = "postgresql+psycopg://sre_control_plane:sre_control_plane@localhost:5432/sre_control_plane"
python -m pytest -m postgresql_integration
```

## Readiness Semantics

`GET /healthz` checks only process liveness.

`GET /readyz` checks database connectivity and verifies that Alembic migrations
have been applied. A reachable database without the `alembic_version` table is
reported as not ready.

## Fake Executor Boundary

The fake executor satisfies the product-neutral adapter interface and returns
deterministic local data. It declares only the accepted MVP read capabilities
and explicitly denies mutation, remediation, merge, incident closeout, and
secret-reading capabilities. It never accesses external systems.

## SRE Replay Executor Boundary

The SRE replay executor is an explicit opt-in mode for validating the first
SRE investigation adapter boundary without live cluster access:

```powershell
$env:SRE_CONTROL_PLANE_EXECUTOR = "sre_replay"
$env:SRE_CONTROL_PLANE_SRE_REPLAY_SCENARIO_ID = "approved-stage-frontend-slo-v1"
$env:SRE_CONTROL_PLANE_SRE_REPLAY_PROVIDERS_JSON = '<exact approved provider declaration JSON>'
```

The approved declaration models read-only Kubernetes, Prometheus, GitOps, and
optional recovery-observation providers for `online-shop-stage`, `frontend`,
the `frontend` rollout, and the `online-shop-stage` Argo CD application. The
adapter accepts only sanitized replay fixtures, exact Prometheus query
allowlists, read-only verbs/actions, and bounded deterministic output. It
fails closed on missing, malformed, broader-than-approved, write-capable, or
unsafe declarations.

This executor does not contact Kubernetes, Prometheus, Argo CD, GitHub,
HolmesGPT, a model, or any SRE Platform runtime. Its results must be treated as
fixture validation only, not live staging, production, recovery, or incident
resolution evidence.

## Workflow Boundary

`POST /v1/sre-investigations` accepts only the canonical MVP request shape and
persists one `READY` task. It does not create an attempt or call the fake
executor. A retry request and a human `retry` decision also only persist
retry-eligible work in `READY`.

`POST /internal/dispatch/tick` is a short, bounded orchestration operation. It
uses the durable `first_sre_dispatch` lease row to atomically claim the oldest
`READY` task, increments its monotonic fencing token, records a `CREATED`
attempt, then commits and releases the database lock before capability
verification. After a successful fail-closed capability check, it records the
durable invocation intent before calling the fake executor. The owner updates
the lease heartbeat and expiry while it persists the bounded handshake. A
non-expired lease prevents a competing tick from claiming work. The current
owner and fencing token are verified before capability, dispatch, and result
state is persisted, so an obsolete owner cannot write a late outcome.

Each tick begins with restart reconciliation before it can claim `READY` work.
For an expired lease or an active attempt without a lease, the tick atomically
claims the existing task and attempt with a new lease owner and fencing token,
then commits before calling the executor's status lookup by the durable
`attempt_id` and idempotency key. A competing tick observes that recovered
lease and cannot claim another attempt while status lookup is in progress.

A confirmed `accepted`, `queued`, or `running` executor status preserves the
same attempt, renews its recovered lease, and blocks new dispatch. The adapter
status contract distinguishes `dispatch_failed` from `failed`: a confirmed
`dispatch_failed` status for a `CAPABILITY_CHECKED` attempt becomes terminal
`DISPATCH_FAILED`; a contradictory dispatch failure after acceptance is
treated as `STALE`. A schema-valid `succeeded` or `partial` result is persisted
as `SUCCEEDED` and moves the task to `AWAITING_HUMAN_REVIEW`. A schema-valid
`failed` result is retained as audit evidence, transitions the attempt to
terminal `FAILED`, and returns the task to `READY`. Confirmed executor
`failed`, `timed_out`, or `cancelled` statuses transition the attempt to the
matching terminal state and return the parent task to `READY`. The terminal
`STALE` state is used when the
invocation identity is missing, status lookup is unavailable or malformed, the
executor reports `stale`, or a confirmed success cannot produce a schema-valid
result. Status and result payloads are revalidated against the canonical
schemas before persistence. In every non-success terminal outcome the recovered
lease is released.

Reconciliation never creates a replacement attempt. A task returned to `READY`
after `FAILED`, `TIMED_OUT`, `CANCELLED`, or `STALE` remains ineligible for
dispatch until an operator or human reviewer records an explicit retry decision.
The reconciliation claim updates the attempt fencing token before the external
lookup, so an outcome from the expired owner is rejected before persistence.

Repeated submission of the same `request_id` with the same payload returns the
existing task. A repeated operational event with the same `signal.fingerprint`
also returns the existing task and creates no new attempt. The same
`request_id` with a different payload is rejected with HTTP `409`.

The workflow records deterministic failure states when the fake executor cannot
accept dispatch or cannot return a schema-valid result. Dispatch failure moves
the attempt to `DISPATCH_FAILED` and the task back to `READY`; malformed or
identity-mismatched results move the attempt to `FAILED` and the task back to
`READY`. A task with a terminal non-success attempt is not dispatch-eligible
again until an operator or human reviewer records an explicit retry decision.
A result is persisted only when its `task_id`, `attempt_id`, and `executor_id`
match the current workflow identity.

The human-review endpoint accepts explicit `complete`, `reject`, or `retry`
decisions while the task is in `AWAITING_HUMAN_REVIEW`. `complete` transitions
the task to `COMPLETED`; `reject` transitions it to terminal `FAILED`; `retry`
requires a `retry_id`, records the human review, and transitions the task back
to `READY`. The next dispatcher tick creates the new attempt, repeats
capability verification, and invokes the fake executor.

`POST /v1/sre-investigations/{task_id}/retry` allows an operator to retry a task
that is already in `READY` after a terminal non-success attempt. Every accepted
retry decision is durable; the following dispatcher tick creates a new
`attempt_id` and keeps previous attempts, transitions,
capability checks, retry decisions, reviews, and results. Reusing the same
`retry_id` with the same task, actor, rationale, source, decision type, and
GitHub reference returns the existing task state and creates no additional
attempt. Reusing it with different decision semantics returns HTTP `409`.
Terminal tasks and tasks with active attempts reject retry requests.

Capability verification exceptions fail closed. The new attempt, rejected
capability check, and terminal `CAPABILITY_REJECTED` attempt state remain
durable while the task remains retry-eligible in `READY`. When the attempt was
claimed from an explicit retry, its retry decision remains durable as well.

Task responses retain the compatible latest `attempt`, `result`, and
`attempt_transitions` fields. They also expose ordered `attempts`, `results`,
and `reviews` histories; each historical attempt includes its own ordered
transitions.

## Evidence And Publication Boundary

`POST /v1/sre-investigations/{task_id}/evidence-publication` accepts a bounded
publication idempotency key only after the latest fake attempt has a
schema-valid `succeeded` or `partial` result. It creates deterministic JSON
evidence containing the normalized request, task and attempt timelines,
capability verification, executor invocation, normalized result, and
limitations. Unsafe strings are rejected before the adapter is called; the
local adapter writes only a SHA-256-named JSON artifact below its configured
root and returns a `local://` URI. No raw logs, credentials, private endpoints,
or machine-local paths are accepted.

Artifact URI, SHA-256, content type, sanitization status, retention policy, and
producing attempt are retained in PostgreSQL. The publisher is a replaceable
interface; the default fake publisher performs no GitHub or network write and
returns a deterministic `fake://publication/...` reference. Publication intent,
payload SHA-256, idempotency key, outcome, error category, and reference are
also retained in PostgreSQL and exposed in task history. Task history also
returns persisted capability checks and executor invocations with its attempts,
results, reviews, transitions, evidence artifacts, and publications.

Evidence-store and publisher calls occur outside database transactions. A
storage error creates no publication record; a publisher error records a
retryable `FAILED_RETRYABLE` or terminal `FAILED_TERMINAL` publication outcome.
Only the former may receive another durable publication claim. Neither outcome rewrites the durable
investigation result, task state, attempt state, or lifecycle transitions.
Reusing the same idempotency key with the same semantic payload reuses the
existing artifact/publication reference. Reusing it for another task, attempt,
or payload returns a conflict.

### GitHub Publication Adapter

`FakePublisher` remains the default. The GitHub adapter is selected only when
the publisher mode is explicitly set to `github` and the publication target
matches an explicit allowlist. Any partial, malformed, unsafe, or non-matching
configuration fails closed during startup:

```powershell
$env:SRE_CONTROL_PLANE_PUBLISHER = "github"
$env:SRE_CONTROL_PLANE_GITHUB_REPOSITORY = "owner/repository"
$env:SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER = "123"
$env:SRE_CONTROL_PLANE_GITHUB_ALLOWED_REPOSITORY = "owner/repository"
$env:SRE_CONTROL_PLANE_GITHUB_ALLOWED_ISSUE_NUMBER = "123"
$env:SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_NAME = "secret-container-name"
$env:SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_VERSION = "1"
$env:SRE_CONTROL_PLANE_GITHUB_TOKEN = "provided-outside-the-repository"
```

The runtime GCP deployment supplies the token only through a Secret Manager
secret reference. Terraform creates the secret container and grants the runtime
service account access only when `github_publisher_mode = "github"`; Terraform
does not create or store the secret version value.

The adapter can call only the configured and allowlisted `owner/repository` and
Issue number. It normalizes GitHub response-header names before classification.
It lists comments through at most three validated pages of 100 entries. Every
pagination URL must use the GitHub API origin and the exact configured comment
path; an unsafe or truncated page sequence fails closed without a write. The
transport does not follow redirects: every `3xx` response is terminal and no
second request is made. It writes deterministic Markdown bounded to 16 KiB and
includes one final hidden marker derived from the publication idempotency key
and semantic payload SHA-256. Marker-like or HTML-comment input is rejected;
a matching canonical final marker reuses the existing comment, while ambiguity
or a marker for the same key with another payload fails closed. Returned comment
ID, body, exact repository path, exact Issue number, and canonical URL fragment
are validated before a durable reference is recorded.

Authentication, authorization, redirects, validation, malformed-response, and
unexpected target failures are terminal. Rate-limit, network, timeout, and
server failures are retryable. Both classes persist append-only failure history
without changing the investigation result or task/attempt lifecycle. The token
is excluded from configuration representations, startup errors, logs, metrics,
and durable history. Metrics expose publication calls and retryable or terminal
failure counters; structured logs omit tokens.

Revision `0007_publication_failure_states` normalizes the legacy `FAILED`
publication status introduced by revision 0006 to `FAILED_RETRYABLE` for both
logical publication intents and append-only publication outcomes. During a
rolling upgrade, runtime also treats the legacy value as retry-eligible. The
downgrade restores only normalized retryable values to `FAILED`.

The live smoke test is deliberately disabled by default. It requires an
explicit operator approval immediately before use and all three variables above
plus the allowlist and credential-reference variables shown above and:

```powershell
$env:SRE_CONTROL_PLANE_GITHUB_LIVE_SMOKE = "1"
python -m pytest -m github_live_smoke
```

It writes only one bounded marked comment to the configured dedicated Issue and
repeats the request to verify reuse. Do not set this opt-in without the required
human approval.

### HolmesGPT HTTP Executor Prototype

`FakeInvestigationExecutor` remains the default executor. The optional
HolmesGPT HTTP executor is a bounded local adapter prototype, not a HolmesGPT
selection or live validation. It accepts a deterministic non-streaming
`/api/chat` fixture response only after fail-closed capability validation and
canonical result normalization.

The adapter configuration is all-or-nothing: endpoint, explicit local-fixture
mode, and a capability declaration must all be present. Local fixture mode
accepts only `http://127.0.0.1` or `http://[::1]`. A non-fixture endpoint must
be private HTTPS by hostname policy, but it fails capability verification until
durable remote status lookup and restart-safe idempotency are proven. That
policy is not proof of private deployment or no public ingress. Fixture
idempotency is explicitly process-local and does not claim restart recovery:
a new adapter instance reports an unknown attempt as `STALE`. The adapter
neither reads nor sends credentials or authorization headers.

The request carries the approved scope, task and attempt identities,
idempotency key, fencing token, read-only flag, and bounded evidence allowlist.
It rejects redirects, unavailable or malformed responses, oversized payloads,
unsafe evidence references, missing capability denials, and identity mismatch.
External HTTP calls remain outside database transactions and locks. A
schema-valid partial result proceeds to human review; a schema-valid failed
result is retained as audit evidence, marks its attempt `FAILED`, and returns
the task to `READY` for an explicit operator retry. Successful responses must
declare a JSON-compatible `Content-Type` before the adapter parses `analysis`.
`cancel_attempt` is explicitly unsupported in this synchronous prototype: it
fails closed without claiming to interrupt an HTTP call or changing a terminal
result.

No HolmesGPT runtime, API authentication behavior, RBAC, Prometheus or logs
toolset enforcement, model behavior, deployment, or live investigation has
been tested. Direct built-in Prometheus or logs access remains a fail-closed
enforcement gap until a bounded proxy or custom toolset is proven.
