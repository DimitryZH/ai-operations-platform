from __future__ import annotations

from collections.abc import Callable

from fastapi import FastAPI, HTTPException, Response

from sre_control_plane.config import Settings, load_settings
from sre_control_plane.contracts import InvestigationRequest
from sre_control_plane.executor import CapabilityReport
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.readiness import ReadinessStatus, check_database_readiness


class ValidationResponse(InvestigationRequest):
    pass


def create_app(
    settings: Settings | None = None,
    readiness_checker: Callable[[], ReadinessStatus] | None = None,
) -> FastAPI:
    active_settings = settings or load_settings()
    active_readiness_checker = readiness_checker or (
        lambda: check_database_readiness(active_settings.database_url)
    )
    fake_executor = FakeInvestigationExecutor()

    app = FastAPI(
        title="SRE Control Plane",
        version="0.1.0",
        description="Local skeleton for the accepted first SRE investigation MVP contract.",
    )

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok", "service": active_settings.service_name}

    @app.get("/readyz", response_model=ReadinessStatus)
    def readyz() -> ReadinessStatus:
        status = active_readiness_checker()
        if status.status != "ok":
            raise HTTPException(status_code=503, detail=status.model_dump())
        return status

    @app.get("/metrics")
    def metrics() -> Response:
        body = (
            "# HELP sre_control_plane_info SRE control-plane skeleton build info\n"
            "# TYPE sre_control_plane_info gauge\n"
            'sre_control_plane_info{service="sre-control-plane",version="0.1.0"} 1\n'
        )
        return Response(content=body, media_type="text/plain; version=0.0.4")

    @app.post("/v1/sre-investigations/validate", response_model=ValidationResponse)
    def validate_investigation(request: InvestigationRequest) -> InvestigationRequest:
        return request

    @app.get("/v1/executors/fake/capabilities", response_model=CapabilityReport)
    def fake_capabilities() -> CapabilityReport:
        return fake_executor.describe_capabilities()

    return app


app = create_app()
