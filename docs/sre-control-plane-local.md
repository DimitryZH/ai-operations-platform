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
- liveness and readiness endpoints

Excluded:

- real investigator or HolmesGPT integration
- full dispatcher, lease, reconciliation, retry, and human-review workflows
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
