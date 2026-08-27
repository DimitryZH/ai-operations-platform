# Local SRE Control-Plane Skeleton

This document describes the first locally runnable skeleton for the accepted
SRE investigation MVP contract. It does not connect to HolmesGPT, Kubernetes,
Prometheus, GitHub publication, cloud resources, or the SRE Platform runtime.

## Scope

Included:

- Python 3.13 FastAPI application
- Pydantic request and result models for schema version `1.0`
- SQLAlchemy table metadata matching the first durable control-plane boundary
- Alembic migration for a fresh local PostgreSQL database
- product-neutral executor interface
- deterministic fake executor for tests and local development
- a database-backed sequential dispatcher with a durable global lease and
  monotonic fencing token
- one bounded local fake-executor workflow from dispatcher tick to human review
- explicit operator-controlled retry that queues retry-eligible local fake tasks
- liveness and readiness endpoints

Excluded:

- real investigator or HolmesGPT integration
- restart reconciliation, automatic retry, timeout, and cancellation workflows
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
