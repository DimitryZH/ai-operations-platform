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


def request_payload() -> dict:
    return json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())


def test_api_runs_fake_workflow_to_human_review(client: TestClient) -> None:
    response = client.post("/v1/sre-investigations", json=request_payload())

    assert response.status_code == 201
    body = response.json()
    assert body["task_state"] == TaskState.AWAITING_HUMAN_REVIEW
    assert body["attempt"]["state"] == "SUCCEEDED"
    assert body["result"]["status"] == "succeeded"

    get_response = client.get(f"/v1/sre-investigations/{body['task_id']}")
    assert get_response.status_code == 200
    assert get_response.json()["task_id"] == body["task_id"]


def test_api_duplicate_submission_returns_existing_task(client: TestClient) -> None:
    first = client.post("/v1/sre-investigations", json=request_payload())
    second = client.post("/v1/sre-investigations", json=request_payload())

    assert first.status_code == 201
    assert second.status_code == 200
    assert second.json()["duplicate_submission"] is True
    assert second.json()["task_id"] == first.json()["task_id"]


def test_api_human_review_complete(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()

    response = client.post(
        f"/v1/sre-investigations/{task['task_id']}/human-review",
        json={
            "decision": "complete",
            "actor": "local-operator",
            "rationale": "Accepted local fake investigation result.",
        },
    )

    assert response.status_code == 200
    assert response.json()["task_state"] == TaskState.COMPLETED


def test_api_human_review_retry_creates_new_attempt(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()
    first_attempt = task["attempt"]["attempt_id"]

    response = client.post(
        f"/v1/sre-investigations/{task['task_id']}/human-review",
        json={
            "decision": "retry",
            "retry_id": "retry-api-human-001",
            "actor": "local-operator",
            "rationale": "Request another fake investigation attempt.",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["task_state"] == TaskState.AWAITING_HUMAN_REVIEW
    assert body["attempt"]["state"] == "SUCCEEDED"
    assert body["attempt"]["attempt_id"] != first_attempt
    assert body["attempt"]["attempt_id"].endswith("-a2")


def test_api_duplicate_human_retry_returns_existing_attempt(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()
    review = {
        "decision": "retry",
        "retry_id": "retry-api-human-duplicate-001",
        "actor": "local-operator",
        "rationale": "Request another fake investigation attempt.",
    }
    first = client.post(f"/v1/sre-investigations/{task['task_id']}/human-review", json=review)
    second = client.post(f"/v1/sre-investigations/{task['task_id']}/human-review", json=review)

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["duplicate_retry_submission"] is True
    assert second.json()["attempt"] == first.json()["attempt"]


def test_api_operator_retry_requires_ready_task(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()

    response = client.post(
        f"/v1/sre-investigations/{task['task_id']}/retry",
        json={
            "retry_id": "retry-api-operator-001",
            "actor": "local-operator",
            "rationale": "Invalid retry while awaiting human review.",
        },
    )

    assert response.status_code == 409


def test_api_operator_retry_creates_new_attempt_after_failure(tmp_path: Path) -> None:
    engine = create_engine(f"sqlite:///{tmp_path / 'api-retry-workflow.db'}")
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, expire_on_commit=False)
    workflow = SreInvestigationWorkflow(session_factory, FailFirstStartExecutor())
    retry_client = TestClient(create_app(workflow=workflow))
    failed = retry_client.post("/v1/sre-investigations", json=request_payload()).json()

    response = retry_client.post(
        f"/v1/sre-investigations/{failed['task_id']}/retry",
        json={
            "retry_id": "retry-api-operator-success-001",
            "actor": "local-operator",
            "rationale": "Retry after fake dispatch failure.",
        },
    )

    assert failed["task_state"] == TaskState.READY
    assert failed["attempt"]["state"] == "DISPATCH_FAILED"
    assert response.status_code == 201
    body = response.json()
    assert body["task_state"] == TaskState.AWAITING_HUMAN_REVIEW
    assert body["attempt"]["state"] == "SUCCEEDED"
    assert body["attempt"]["attempt_id"].endswith("-a2")


def test_api_invalid_human_review_transition_returns_409(client: TestClient) -> None:
    task = client.post("/v1/sre-investigations", json=request_payload()).json()
    review = {
        "decision": "complete",
        "actor": "local-operator",
        "rationale": "Accepted local fake investigation result.",
    }
    first = client.post(f"/v1/sre-investigations/{task['task_id']}/human-review", json=review)
    second = client.post(f"/v1/sre-investigations/{task['task_id']}/human-review", json=review)

    assert first.status_code == 200
    assert second.status_code == 409


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
