from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from sre_control_plane.app import create_app
from sre_control_plane.executor import ExecutorStatus, StartInvestigationResponse
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.persistence import Base
from sre_control_plane.states import TaskState
from sre_control_plane.workflow import SreInvestigationWorkflow

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture()
def client(tmp_path: Path) -> TestClient:
    engine = create_engine(f"sqlite:///{tmp_path / 'api-workflow.db'}")
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    workflow = SreInvestigationWorkflow(session_factory, FakeInvestigationExecutor())
    return TestClient(create_app(workflow=workflow))


def request_payload(request_id: str = "req-20260813-stage-001") -> dict:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    payload["request_id"] = request_id
    payload["signal"]["fingerprint"] = request_id
    return payload


def run_tick(client: TestClient, owner: str = "api-tick") -> dict:
    response = client.post("/internal/dispatch/tick", json={"lease_owner": owner})
    assert response.status_code == 200
    return response.json()


def test_api_intake_persists_ready_task_without_invocation(client: TestClient) -> None:
    response = client.post("/v1/sre-investigations", json=request_payload())

    assert response.status_code == 201
    body = response.json()
    assert body["task_state"] == TaskState.READY
    assert body["attempt"] is None
    assert run_tick(client)["task_id"] == body["task_id"]


def test_api_tick_runs_one_fake_workflow_to_human_review(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()
    tick = run_tick(client)
    state = client.get(f"/v1/sre-investigations/{task['task_id']}").json()

    assert tick["dispatched"] is True
    assert tick["fencing_token"] == 1
    assert state["task_state"] == TaskState.AWAITING_HUMAN_REVIEW
    assert state["attempt"]["state"] == "SUCCEEDED"


def test_api_human_retry_waits_for_a_following_tick(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()
    run_tick(client)
    review = client.post(
        f"/v1/sre-investigations/{task['task_id']}/human-review",
        json={
            "decision": "retry",
            "retry_id": "retry-api-human-001",
            "actor": "local-operator",
            "rationale": "Request another fake investigation attempt.",
        },
    )

    assert review.status_code == 200
    assert review.json()["task_state"] == TaskState.READY
    assert len(review.json()["attempts"]) == 1
    run_tick(client, "api-tick-retry")
    retried = client.get(f"/v1/sre-investigations/{task['task_id']}").json()
    assert retried["attempt"]["attempt_id"].endswith("-a2")


def test_api_history_includes_attempts_results_reviews_and_fencing(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()
    run_tick(client)
    client.post(
        f"/v1/sre-investigations/{task['task_id']}/human-review",
        json={
            "decision": "retry",
            "retry_id": "retry-api-history-001",
            "actor": "local-operator",
            "rationale": "Request another fake investigation attempt.",
        },
    )
    run_tick(client, "api-tick-history")
    history = client.get(f"/v1/sre-investigations/{task['task_id']}").json()

    assert len(history["attempts"]) == 2
    assert len(history["results"]) == 2
    assert len(history["reviews"]) == 1
    assert history["attempts"][0]["transitions"][-1]["fencing_token"] == 1
    assert history["attempts"][1]["transitions"][-1]["fencing_token"] == 2


def test_api_duplicate_submission_and_retry_remain_idempotent(client: TestClient) -> None:
    first = client.post("/v1/sre-investigations", json=request_payload())
    second = client.post("/v1/sre-investigations", json=request_payload())

    assert first.status_code == 201
    assert second.status_code == 200
    assert second.json()["duplicate_submission"] is True


def test_api_metrics_expose_dispatch_counters(client: TestClient) -> None:
    client.post("/v1/sre-investigations", json=request_payload())
    run_tick(client)
    metrics = client.get("/metrics")

    assert metrics.status_code == 200
    assert "sre_control_plane_dispatch_ticks_total 1" in metrics.text
    assert "sre_control_plane_dispatch_claims_total 1" in metrics.text


def test_api_retry_after_dispatch_failure_waits_for_tick(tmp_path: Path) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'api-retry-workflow.db'}")
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    workflow = SreInvestigationWorkflow(session_factory, FailFirstStartExecutor())
    retry_client = TestClient(create_app(workflow=workflow))
    task = retry_client.post("/v1/sre-investigations", json=request_payload()).json()
    run_tick(retry_client, "api-failing-tick")

    retry = retry_client.post(
        f"/v1/sre-investigations/{task['task_id']}/retry",
        json={
            "retry_id": "retry-api-operator-001",
            "actor": "local-operator",
            "rationale": "Retry after fake dispatch failure.",
        },
    )

    assert retry.status_code == 201
    assert retry.json()["task_state"] == TaskState.READY
    assert len(retry.json()["attempts"]) == 1
    run_tick(retry_client, "api-retry-tick")
    assert retry_client.get(f"/v1/sre-investigations/{task['task_id']}").json()[
        "attempt"
    ]["attempt_id"].endswith("-a2")


class FailFirstStartExecutor(FakeInvestigationExecutor):
    def __init__(self) -> None:
        super().__init__()
        self.start_count = 0

    def start_investigation(self, command):
        self.start_count += 1
        if self.start_count == 1:
            return StartInvestigationResponse(
                executor_id=self.executor_id,
                attempt_id=command.attempt_id,
                status=ExecutorStatus.FAILED,
                idempotency_key=command.idempotency_key,
                fencing_token=command.fencing_token,
            )
        return super().start_investigation(command)
