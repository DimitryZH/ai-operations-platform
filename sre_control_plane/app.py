from __future__ import annotations

from collections.abc import Callable

from fastapi import FastAPI, HTTPException, Response

from sre_control_plane.config import Settings, create_executor, create_publisher, load_settings
from sre_control_plane.contracts import InvestigationRequest
from sre_control_plane.database import create_session_factory
from sre_control_plane.executor import CapabilityReport
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.readiness import ReadinessStatus, check_database_readiness
from sre_control_plane.workflow import (
    DuplicateRequestConflict,
    DuplicateRetryConflict,
    DispatchTickRequest,
    DispatchTickView,
    EvidencePublicationRequest,
    HumanReviewRequest,
    InvalidStateTransition,
    PublicationConflict,
    RetryRequest,
    SreInvestigationWorkflow,
    TaskNotFound,
    TaskView,
)


class ValidationResponse(InvestigationRequest):
    pass


def create_app(
    settings: Settings | None = None,
    readiness_checker: Callable[[], ReadinessStatus] | None = None,
    workflow: SreInvestigationWorkflow | None = None,
) -> FastAPI:
    active_settings = settings or load_settings()
    active_readiness_checker = readiness_checker or (
        lambda: check_database_readiness(active_settings.database_url)
    )
    executor = create_executor(active_settings)
    active_workflow = workflow or SreInvestigationWorkflow(
        create_session_factory(active_settings.database_url),
        executor,
        publisher=create_publisher(active_settings),
    )

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
        dispatch_metrics = active_workflow.dispatch_metrics()
        publication_metrics = active_workflow.publication_metrics()
        body = (
            "# HELP sre_control_plane_info SRE control-plane skeleton build info\n"
            "# TYPE sre_control_plane_info gauge\n"
            'sre_control_plane_info{service="sre-control-plane",version="0.1.0"} 1\n'
            "# HELP sre_control_plane_dispatch_ticks_total Bounded dispatcher ticks\n"
            "# TYPE sre_control_plane_dispatch_ticks_total counter\n"
            f"sre_control_plane_dispatch_ticks_total {dispatch_metrics['ticks_total']}\n"
            "# HELP sre_control_plane_dispatch_claims_total Successful durable dispatch claims\n"
            "# TYPE sre_control_plane_dispatch_claims_total counter\n"
            f"sre_control_plane_dispatch_claims_total {dispatch_metrics['claims_total']}\n"
            "# HELP sre_control_plane_dispatch_lease_blocked_total Ticks blocked by an active lease\n"
            "# TYPE sre_control_plane_dispatch_lease_blocked_total counter\n"
            f"sre_control_plane_dispatch_lease_blocked_total {dispatch_metrics['lease_blocked_total']}\n"
            "# HELP sre_control_plane_stale_fencing_total Obsolete outcomes ignored\n"
            "# TYPE sre_control_plane_stale_fencing_total counter\n"
            f"sre_control_plane_stale_fencing_total {dispatch_metrics['stale_fencing_total']}\n"
            "# HELP sre_control_plane_publication_calls_total Publication adapter calls\n"
            "# TYPE sre_control_plane_publication_calls_total counter\n"
            f"sre_control_plane_publication_calls_total {publication_metrics['calls_total']}\n"
            "# HELP sre_control_plane_publication_failures_total Publication adapter failures by classification\n"
            "# TYPE sre_control_plane_publication_failures_total counter\n"
            f"sre_control_plane_publication_failures_total{{classification=\"retryable\"}} {publication_metrics['retryable_failures_total']}\n"
            f"sre_control_plane_publication_failures_total{{classification=\"terminal\"}} {publication_metrics['terminal_failures_total']}\n"
        )
        return Response(content=body, media_type="text/plain; version=0.0.4")

    @app.post("/v1/sre-investigations/validate", response_model=ValidationResponse)
    def validate_investigation(request: InvestigationRequest) -> InvestigationRequest:
        return request

    @app.post("/v1/sre-investigations", response_model=TaskView, status_code=201)
    def submit_investigation(request: InvestigationRequest, response: Response) -> TaskView:
        try:
            task = active_workflow.submit_request(request)
        except DuplicateRequestConflict as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        if task.duplicate_submission:
            response.status_code = 200
        return task

    @app.get("/v1/sre-investigations/{task_id}", response_model=TaskView)
    def get_investigation(task_id: str) -> TaskView:
        try:
            return active_workflow.get_task(task_id)
        except TaskNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    @app.post(
        "/v1/sre-investigations/{task_id}/evidence-publication",
        response_model=TaskView,
    )
    def publish_evidence(task_id: str, publication: EvidencePublicationRequest) -> TaskView:
        try:
            return active_workflow.publish_evidence(task_id, publication)
        except TaskNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except (InvalidStateTransition, PublicationConflict) as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.post("/v1/sre-investigations/{task_id}/retry", response_model=TaskView, status_code=201)
    def retry_investigation(task_id: str, retry: RetryRequest, response: Response) -> TaskView:
        try:
            task = active_workflow.retry_task(task_id, retry)
        except TaskNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except (DuplicateRetryConflict, InvalidStateTransition) as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        if task.duplicate_retry_submission:
            response.status_code = 200
        return task

    @app.post("/internal/dispatch/tick", response_model=DispatchTickView)
    def dispatch_tick(request: DispatchTickRequest) -> DispatchTickView:
        return active_workflow.run_dispatch_tick(request.lease_owner)

    @app.post("/v1/sre-investigations/{task_id}/human-review", response_model=TaskView)
    def record_human_review(task_id: str, review: HumanReviewRequest) -> TaskView:
        try:
            return active_workflow.record_human_review(task_id, review)
        except TaskNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except (DuplicateRetryConflict, InvalidStateTransition) as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc

    @app.get("/v1/executors/fake/capabilities", response_model=CapabilityReport)
    def fake_capabilities() -> CapabilityReport:
        return FakeInvestigationExecutor().describe_capabilities()

    return app


app = create_app()
