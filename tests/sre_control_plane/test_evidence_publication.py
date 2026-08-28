from __future__ import annotations

import json
import threading
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from sre_control_plane.app import create_app
from sre_control_plane.contracts import InvestigationRequest
from sre_control_plane.evidence import (
    EvidenceStoreError,
    LocalFilesystemEvidenceStore,
    MAX_EVIDENCE_PACKAGE_BYTES,
    StoredEvidence,
    build_evidence_package,
)
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.persistence import (
    Base,
    EvidenceArtifactRecord,
    GitHubPublicationRecord,
    InvestigationResultRecord,
    PublicationIntentRecord,
)
from sre_control_plane.publisher import FakePublisher, PublicationError, PublicationReceipt
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
    assert [publication.status for publication in retried.publications] == ["FAILED", "PUBLISHED"]
    assert [publication.attempt_sequence for publication in retried.publications] == [1, 2]
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
    assert body["publications"][0]["attempt_sequence"] == 1
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


def test_concurrent_requests_share_one_durable_publisher_claim(session_factory, tmp_path: Path) -> None:
    publisher = BlockingPublisher()
    workflow, task = completed_workflow(session_factory, tmp_path, publisher)
    outcomes = []

    def publish() -> None:
        outcomes.append(workflow.publish_evidence(
            task.task_id, EvidencePublicationRequest(idempotency_key="publication-concurrent")
        ))

    first = threading.Thread(target=publish)
    second = threading.Thread(target=publish)
    first.start()
    assert publisher.started.wait(timeout=5)
    second.start()
    publisher.release.set()
    first.join(timeout=5)
    second.join(timeout=5)

    assert not first.is_alive() and not second.is_alive()
    assert publisher.calls == 1
    with session_factory() as session:
        intent = session.scalar(select(PublicationIntentRecord))
        records = session.scalars(select(GitHubPublicationRecord)).all()
    assert intent is not None and intent.status == "PUBLISHED" and intent.active_claim_token is None
    assert len(records) == 1
    assert any(view.publications and view.publications[0].status == "PUBLISHED" for view in outcomes)


def test_evidence_store_failure_is_durable_and_does_not_change_lifecycle(session_factory, tmp_path: Path) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    workflow._evidence_store = FailingStore()

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="store-failure"))

    assert view.failure_reason == "publication_failed_retryable"
    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert view.attempt is not None and view.attempt.state == AttemptState.SUCCEEDED
    assert view.publications[0].status == "FAILED"
    assert view.publications[0].error_category == "EvidenceStoreError"
    assert view.evidence_artifacts == []


@pytest.mark.parametrize("store_factory", [lambda: MalformedStore(), lambda: UnsafeStore()])
def test_invalid_evidence_store_response_has_controlled_failure(session_factory, tmp_path: Path, store_factory) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    workflow._evidence_store = store_factory()

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="invalid-store"))

    assert view.failure_reason == "publication_failed_retryable"
    assert view.publications[0].status == "FAILED"
    assert view.evidence_artifacts == []


@pytest.mark.parametrize("publisher_factory", [lambda: MalformedReceiptPublisher(), lambda: UnsafeReceiptPublisher()])
def test_invalid_publisher_receipt_has_controlled_failure(session_factory, tmp_path: Path, publisher_factory) -> None:
    publisher = publisher_factory()
    workflow, task = completed_workflow(session_factory, tmp_path, publisher)

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="invalid-receipt"))

    assert view.failure_reason == "publication_failed_retryable"
    assert view.publications[0].status == "FAILED"
    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW


@pytest.mark.parametrize(
    ("payload_extension", "idempotency_key"),
    [
        ({"bounded_padding": "x" * (MAX_EVIDENCE_PACKAGE_BYTES + 1)}, "oversized"),
        ({"bounded_collection": ["entry"] * 101}, "collection-bound"),
    ],
)
def test_evidence_bounds_have_durable_failure_history(
    session_factory, tmp_path: Path, monkeypatch, payload_extension, idempotency_key,
) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    original_snapshot = workflow._publication_snapshot

    def expanded_snapshot(session, task_record):
        attempt, result, payload = original_snapshot(session, task_record)
        return attempt, result, {**payload, **payload_extension}

    monkeypatch.setattr(workflow, "_publication_snapshot", expanded_snapshot)
    with session_factory() as session:
        result_before = session.scalar(select(InvestigationResultRecord))
        assert result_before is not None
        result_payload_before = result_before.payload

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key=idempotency_key))

    assert view.failure_reason == "publication_failed_retryable"
    assert view.publications[0].status == "FAILED"
    assert view.evidence_artifacts == []
    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert view.attempt is not None and view.attempt.state == AttemptState.SUCCEEDED
    with session_factory() as session:
        result_after = session.scalar(select(InvestigationResultRecord))
    assert result_after is not None and result_after.payload == result_payload_before


def test_late_failure_cannot_overwrite_confirmed_publication(session_factory, tmp_path: Path) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    completed = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="late-outcome"))
    with session_factory() as session:
        publication = session.scalar(select(GitHubPublicationRecord))
    assert publication is not None

    view = workflow._finalize_publication(
        task.task_id, publication.id, "obsolete-claim", "FAILED", None, "PublicationError", "ignored"
    )

    assert view.publications[0].status == "PUBLISHED"


def test_concurrent_artifact_creation_keeps_one_durable_artifact(session_factory, tmp_path: Path) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    task = workflow.get_task(task.task_id)
    assert task.attempt is not None
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})
    outcomes: list[StoredEvidence] = []
    failures: list[Exception] = []

    def store() -> None:
        try:
            outcomes.append(workflow._store_evidence(task.attempt.attempt_id, package))
        except Exception as exc:  # the assertion below keeps concurrent errors visible
            failures.append(exc)

    first = threading.Thread(target=store)
    second = threading.Thread(target=store)
    first.start()
    second.start()
    first.join(timeout=5)
    second.join(timeout=5)

    assert not failures
    assert len(outcomes) == 2
    with session_factory() as session:
        assert len(session.scalars(select(EvidenceArtifactRecord)).all()) == 1


class BlockingPublisher(FakePublisher):
    def __init__(self) -> None:
        super().__init__()
        self.calls = 0
        self.started = threading.Event()
        self.release = threading.Event()

    def publish(self, request):
        self.calls += 1
        self.started.set()
        assert self.release.wait(timeout=5)
        return super().publish(request)


class FailingStore:
    def store(self, package):
        raise EvidenceStoreError("local evidence storage unavailable")


class MalformedStore:
    def store(self, package):
        return {"artifact_uri": "local://evidence/evidence-bad.json"}


class UnsafeStore:
    def store(self, package):
        return StoredEvidence(
            artifact_uri="https://untrusted.example/evidence.json",
            sha256=package.sha256,
            content_type="application/json",
            sanitization_status="SANITIZED",
            retention_policy="local-development-30d",
        )


class MalformedReceiptPublisher:
    def publish(self, request):
        return {"reference": "fake://publication/not-a-valid-reference"}


class UnsafeReceiptPublisher:
    def publish(self, request):
        return PublicationReceipt(reference="https://github.example/publication/1")
