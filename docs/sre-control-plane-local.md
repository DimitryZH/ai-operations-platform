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
- one deterministic local fake-executor workflow from request intake to human
  review
- explicit operator-controlled retry for retry-eligible local fake tasks
- liveness and readiness endpoints

Excluded:

- real investigator or HolmesGPT integration
- full dispatcher, lease, reconciliation, automatic retry, and restart recovery
  workflows
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

Run one deterministic fake investigation:

```powershell
$task = Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -InFile .\examples\sre-investigation-request.json `
  http://127.0.0.1:8000/v1/sre-investigations

$task.task_state
```

The expected task state after the fake investigation is
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

Retry an eligible task that has returned to `READY` after a failed attempt:

```powershell
Invoke-RestMethod `
  -Method Post `
  -ContentType "application/json" `
  -Body '{"retry_id":"retry-local-operator-001","actor":"local-operator","rationale":"Retry after the previous terminal non-success attempt."}' `
  "http://127.0.0.1:8000/v1/sre-investigations/$($task.task_id)/retry"
```

Run tests:

```powershell
python -m pytest
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

`POST /v1/sre-investigations` accepts only the canonical MVP request shape,
persists one task and first attempt, verifies fake executor capabilities,
records transition rows, invokes the fake executor once, validates the
normalized result, persists the result, and stops the task at
`AWAITING_HUMAN_REVIEW`.

Repeated submission of the same `request_id` with the same payload returns the
existing task. A repeated operational event with the same `signal.fingerprint`
also returns the existing task and creates no new attempt. The same
`request_id` with a different payload is rejected with HTTP `409`.

The workflow records deterministic failure states when the fake executor cannot
accept dispatch or cannot return a schema-valid result. Dispatch failure moves
the attempt to `DISPATCH_FAILED` and the task back to `READY`; malformed or
identity-mismatched results move the attempt to `FAILED` and the task back to
`READY`. A result is persisted only when its `task_id`, `attempt_id`, and
`executor_id` match the current workflow identity.

The human-review endpoint accepts explicit `complete`, `reject`, or `retry`
decisions while the task is in `AWAITING_HUMAN_REVIEW`. `complete` transitions
the task to `COMPLETED`; `reject` transitions it to terminal `FAILED`; `retry`
requires a `retry_id`, records the human review, transitions the task back to
`READY`, creates a new attempt, repeats capability verification, and runs the
fake executor again.

`POST /v1/sre-investigations/{task_id}/retry` allows an operator to retry a task
that is already in `READY` after a terminal non-success attempt. Every accepted
retry creates a new `attempt_id` and keeps previous attempts, transitions,
capability checks, retry decisions, reviews, and results. Reusing the same
`retry_id` with the same task, actor, rationale, source, decision type, and
GitHub reference returns the existing task state and creates no additional
attempt. Reusing it with different decision semantics returns HTTP `409`.
Terminal tasks and tasks with active attempts reject retry requests.

Capability verification exceptions fail closed. The retry decision, new
attempt, rejected capability check, and terminal `CAPABILITY_REJECTED` attempt
state remain durable while the task remains retry-eligible in `READY`.

Task responses retain the compatible latest `attempt`, `result`, and
`attempt_transitions` fields. They also expose ordered `attempts`, `results`,
and `reviews` histories; each historical attempt includes its own ordered
transitions.
