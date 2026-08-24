from __future__ import annotations

from fastapi.testclient import TestClient

from sre_control_plane.app import create_app
from sre_control_plane.readiness import ReadinessStatus


def test_health_endpoint() -> None:
    client = TestClient(create_app())

    response = client.get("/healthz")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_ready_endpoint_ok_with_injected_checker() -> None:
    app = create_app(
        readiness_checker=lambda: ReadinessStatus(status="ok", database="ok", migrations="ok")
    )
    client = TestClient(app)

    response = client.get("/readyz")

    assert response.status_code == 200
    assert response.json()["migrations"] == "ok"


def test_ready_endpoint_returns_503_when_database_not_ready() -> None:
    app = create_app(
        readiness_checker=lambda: ReadinessStatus(
            status="not_ready",
            database="failed",
            migrations="unknown",
            detail="OperationalError",
        )
    )
    client = TestClient(app)

    response = client.get("/readyz")

    assert response.status_code == 503
    assert response.json()["detail"]["database"] == "failed"


def test_validate_endpoint_rejects_mutation_constraints() -> None:
    client = TestClient(create_app())
    payload = {
        "schema_version": "1.0",
        "request_id": "req-invalid",
        "source": {"type": "operator", "system": "sre-platform"},
        "scenario": {
            "type": "slo_investigation",
            "environment": "staging",
            "service": "frontend",
            "summary": "Invalid request",
        },
        "scope": {
            "cluster": "sre-platform-staging",
            "namespace": "online-shop-stage",
            "workload": "frontend",
            "rollout": "frontend",
            "gitops_application": "online-shop-stage",
            "time_range": {
                "start": "2026-08-13T15:00:00Z",
                "end": "2026-08-13T15:20:00Z",
            },
        },
        "signal": {
            "status": "manual",
            "name": "frontend-stage-error-ratio",
            "fingerprint": "req-invalid",
            "observed_at": "2026-08-13T15:05:00Z",
        },
        "requested_capabilities": [
            "kubernetes.read",
            "prometheus.query",
            "rollout.read",
            "gitops.read",
            "logs.read",
            "investigation.report",
        ],
        "constraints": {
            "read_only": False,
            "allow_mutation": True,
            "require_human_closeout": True,
        },
    }

    response = client.post("/v1/sre-investigations/validate", json=payload)

    assert response.status_code == 422


def test_fake_capabilities_endpoint() -> None:
    client = TestClient(create_app())

    response = client.get("/v1/executors/fake/capabilities")

    assert response.status_code == 200
    assert response.json()["supports_idempotent_start"] is True
    assert "remediation.execute" in response.json()["denied_capabilities"]
