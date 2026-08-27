from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from sre_control_plane.app import create_app
from sre_control_plane.contracts import InvestigationRequest
from sre_control_plane.evidence import EvidenceStoreError, LocalFilesystemEvidenceStore, build_evidence_package
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.persistence import Base, GitHubPublicationRecord, InvestigationResultRecord
from sre_control_plane.publisher import FakePublisher, PublicationError
from sre_control_plane.states import AttemptState, TaskState
from sre_control_plane.workflow import (
    EvidencePublicationRequest,
    PublicationConflict,
    SreInvestigationWorkflow,
)

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture()
def session_factory(tmp_path: Path):
    engine = create_engine(f"sqlite:///{tmp_path / 'evidence.db'}")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine, expire_on_commit=False)


def request_example() -> InvestigationRequest:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    payload["request_id"] = "evidence-request"
    payload["signal"]["fingerprint"] = "evidence-request"
    return InvestigationRequest.model_validate(payload)


def completed_workflow(session_factory, tmp_path: Path, publisher=None):
    workflow = SreInvestigationWorkflow(
        session_factory,
        FakeInvestigationExecutor(),
        evidence_store=LocalFilesystemEvidenceStore(tmp_path / "evidence"),
        publisher=publisher,
    )
    task = workflow.submit_request(request_example())
    workflow.run_dispatch_tick("evidence-tick")
    return workflow, task


def test_evidence_package_rejects_unsafe_content() -> None:
    with pytest.raises(EvidenceStoreError):
        build_evidence_package({"message": "token=not-allowed"})


def test_publication_persists_sanitized_integrity_checked_artifact(session_factory, tmp_path: Path) -> None:
    publisher = CountingPublisher()
    workflow, task = completed_workflow(session_factory, tmp_path, publisher)

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))
    repeated = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))

    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert view.evidence_artifacts[0].sanitization_status == "SANITIZED"
    assert len(repeated.evidence_artifacts) == 1
    assert repeated.publications[0].status == "PUBLISHED"
    assert repeated.publications[0].github_reference.startswith("fake://publication/")
    assert len(repeated.publications[0].payload_sha256) == 64
    assert publisher.calls == 1


def test_publication_rejects_same_key_with_changed_semantics(session_factory, tmp_path: Path) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))
    with session_factory.begin() as session:
        result = session.scalar(select(InvestigationResultRecord))
        assert result is not None
        result.payload = {**result.payload, "summary": "A different bounded summary."}

    with pytest.raises(PublicationConflict):
        workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))


def test_publication_failure_is_retryable_without_lifecycle_mutation(session_factory, tmp_path: Path) -> None:
    publisher = FailingPublisher()
    workflow, task = completed_workflow(session_factory, tmp_path, publisher)

    failed = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))
    assert failed.failure_reason == "publication_failed_retryable"
    assert failed.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert failed.attempt is not None and failed.attempt.state == AttemptState.SUCCEEDED
    assert failed.publications[0].status == "FAILED"

    publisher.fail = False
    retried = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))
    assert retried.publications[0].status == "PUBLISHED"
    assert len(retried.evidence_artifacts) == 1


def test_task_api_exposes_evidence_and_publication_history(session_factory, tmp_path: Path) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))
    client = TestClient(create_app(workflow=workflow))

    response = client.get(f"/v1/sre-investigations/{task.task_id}")

    assert response.status_code == 200
    body = response.json()
    assert body["evidence_artifacts"][0]["sha256"]
    assert body["publications"][0]["status"] == "PUBLISHED"
    assert body["attempts"][0]["transitions"]
    assert body["results"]
    assert body["capability_checks"]
    assert body["executor_invocations"]


class CountingPublisher(FakePublisher):
    def __init__(self) -> None:
        super().__init__()
        self.calls = 0

    def publish(self, request):
        self.calls += 1
        return super().publish(request)


class FailingPublisher(FakePublisher):
    def __init__(self) -> None:
        super().__init__()
        self.fail = True

    def publish(self, request):
        if self.fail:
            raise PublicationError("local publisher unavailable")
        return super().publish(request)
