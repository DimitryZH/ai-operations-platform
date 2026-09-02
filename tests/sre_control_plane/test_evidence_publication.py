from __future__ import annotations

import json
import hashlib
import logging
import threading
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from sre_control_plane.app import create_app
from sre_control_plane.contracts import InvestigationRequest
from sre_control_plane.evidence import (
    EVIDENCE_CONTENT_TYPE,
    EvidenceStoreError,
    EvidencePackage,
    GcsEvidenceStore,
    LocalFilesystemEvidenceStore,
    MAX_EVIDENCE_PACKAGE_BYTES,
    StoredEvidence,
    TerminalEvidenceStoreError,
    build_evidence_package,
    gcs_evidence_object_name,
    validate_stored_evidence,
)
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.persistence import (
    Base,
    EvidenceArtifactRecord,
    GitHubPublicationRecord,
    InvestigationResultRecord,
    PublicationIntentRecord,
)
from sre_control_plane.publisher import (
    FakePublisher,
    PublicationError,
    PublicationReceipt,
    TerminalPublicationError,
)
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


def test_gcs_evidence_store_writes_deterministic_bounded_object() -> None:
    client = FakeGcsClient()
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=client,
    )
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})

    stored = store.store(package)

    blob = client.bucket_ref.blobs[gcs_evidence_object_name(package.sha256)]
    assert blob.if_generation_match == 0
    assert blob.content == package.content
    assert blob.content_type == "application/json"
    assert blob.metadata["sha256"] == package.sha256
    assert stored.artifact_uri == (
        "gs://ai-operations-platform-507220-sre-cp-staging-evidence/"
        f"evidence/sha256/{package.sha256}.json"
    )
    assert validate_stored_evidence(stored, package) == stored


def test_gcs_evidence_store_repeated_identical_write_is_idempotent() -> None:
    client = FakeGcsClient()
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=client,
    )
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})

    first = store.store(package)
    second = store.store(package)

    blob = client.bucket_ref.blobs[gcs_evidence_object_name(package.sha256)]
    assert first == second
    assert blob.upload_calls == 2
    assert blob.download_calls == 2


def test_gcs_evidence_store_conflicting_existing_identity_fails_closed() -> None:
    store, blob, package = existing_gcs_artifact()
    blob.content = b" " + package.content[1:]

    with pytest.raises(TerminalEvidenceStoreError, match="different content"):
        store.store(package)


def test_gcs_evidence_store_conflicting_existing_metadata_fails_closed() -> None:
    store, blob, package = existing_gcs_artifact()
    blob.remote_metadata = {
        "sha256": package.sha256,
        "sanitization_status": "UNREVIEWED",
        "content_type": EVIDENCE_CONTENT_TYPE,
        "identity": f"sha256:{package.sha256}",
    }

    with pytest.raises(TerminalEvidenceStoreError, match="unexpected metadata"):
        store.store(package)


@pytest.mark.parametrize(
    "metadata",
    [
        None,
        {},
        {"sha256": "0" * 64},
        {
            "sha256": "0" * 64,
            "sanitization_status": "SANITIZED",
            "content_type": EVIDENCE_CONTENT_TYPE,
            "identity": "sha256:" + ("0" * 64),
            "extra": "unexpected",
        },
        {
            "sha256": "0" * 64,
            "sanitization_status": "SANITIZED",
            "content_type": EVIDENCE_CONTENT_TYPE,
            "identity": "sha256:" + ("0" * 64),
            "unsafe key": "unexpected",
        },
        {
            "sha256": "0" * 64,
            "sanitization_status": "SANITIZED",
            "content_type": EVIDENCE_CONTENT_TYPE,
            "identity": "sha256:unsafe value with spaces",
        },
        {
            "sha256": "0" * 64,
            "sanitization_status": "SANITIZED",
            "content_type": EVIDENCE_CONTENT_TYPE,
            "identity": "sha256:" + ("1" * 64),
        },
    ],
)
def test_gcs_evidence_store_requires_exact_metadata_contract(metadata) -> None:
    store, blob, package = existing_gcs_artifact()
    blob.remote_metadata = metadata

    with pytest.raises(TerminalEvidenceStoreError):
        store.store(package)


@pytest.mark.parametrize("content_type", [None, "text/plain"])
def test_gcs_evidence_store_requires_exact_content_type(content_type) -> None:
    store, blob, package = existing_gcs_artifact()
    blob.remote_content_type = content_type

    with pytest.raises(TerminalEvidenceStoreError, match="content type"):
        store.store(package)


@pytest.mark.parametrize("remote_size", [None, "123", -1, MAX_EVIDENCE_PACKAGE_BYTES + 1])
def test_gcs_evidence_store_requires_valid_remote_size(remote_size) -> None:
    store, blob, package = existing_gcs_artifact()
    blob.remote_size = remote_size

    with pytest.raises(TerminalEvidenceStoreError, match="size"):
        store.store(package)


def test_gcs_evidence_store_requires_remote_size_to_match_expected_size() -> None:
    store, blob, package = existing_gcs_artifact()
    blob.remote_size = len(package.content) + 1

    with pytest.raises(TerminalEvidenceStoreError, match="size"):
        store.store(package)


def test_gcs_evidence_store_missing_remote_object_fails_closed() -> None:
    client = FakeGcsClient()
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=client,
    )
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})
    client.bucket_ref.missing_on_get = True

    with pytest.raises(TerminalEvidenceStoreError, match="missing"):
        store.store(package)


def test_gcs_evidence_store_rejects_oversized_readback() -> None:
    store, blob, package = existing_gcs_artifact()
    blob.download_content = package.content + b"x"
    blob.ignore_range = True

    with pytest.raises(TerminalEvidenceStoreError, match="readback size"):
        store.store(package)


def test_gcs_evidence_store_rejects_readback_integrity_mismatch() -> None:
    store, blob, package = existing_gcs_artifact()
    blob.content = b" " + package.content[1:]

    with pytest.raises(TerminalEvidenceStoreError, match="different content"):
        store.store(package)


@pytest.mark.parametrize("failure", [TimeoutError("provider detail should not leak"), ConnectionError("provider detail should not leak")])
def test_gcs_evidence_store_retryable_timeout_or_network_failure_is_sanitized(failure, caplog) -> None:
    store, blob, package = existing_gcs_artifact()
    blob.download_error = failure
    caplog.set_level(logging.DEBUG)

    with pytest.raises(EvidenceStoreError, match="readback failed") as exc_info:
        store.store(package)
    assert not isinstance(exc_info.value, TerminalEvidenceStoreError)
    assert_sanitized_provider_failure(exc_info.value, caplog)


@pytest.mark.parametrize("status_code", [429, 500, 502, 503, 504])
def test_gcs_evidence_store_retryable_status_failures_are_allowlisted(status_code, caplog) -> None:
    client = FakeGcsClient(upload_error=FakeGcsStatusError(status_code))
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=client,
    )
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})
    caplog.set_level(logging.DEBUG)

    with pytest.raises(EvidenceStoreError, match="storage unavailable") as exc_info:
        store.store(package)
    assert not isinstance(exc_info.value, TerminalEvidenceStoreError)
    assert_sanitized_provider_failure(exc_info.value, caplog)


@pytest.mark.parametrize("status_code", [400, 401, 403, 404, 409])
def test_gcs_evidence_store_terminal_status_failures_fail_closed(status_code, caplog) -> None:
    client = FakeGcsClient(upload_error=FakeGcsStatusError(status_code))
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=client,
    )
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})
    caplog.set_level(logging.DEBUG)

    with pytest.raises(TerminalEvidenceStoreError, match="rejected") as exc_info:
        store.store(package)
    assert_sanitized_provider_failure(exc_info.value, caplog)


@pytest.mark.parametrize("operation", ["upload", "lookup", "metadata", "readback"])
def test_gcs_evidence_store_unknown_provider_exception_is_terminal(operation, caplog) -> None:
    failure = FakeUnknownProviderError("provider detail should not leak")
    if operation == "upload":
        client = FakeGcsClient(upload_error=failure)
        store = GcsEvidenceStore(
            "ai-operations-platform-507220",
            "ai-operations-platform-507220-sre-cp-staging-evidence",
            client=client,
        )
        package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})
    else:
        store, blob, package = existing_gcs_artifact()
        if operation == "lookup":
            store._bucket.get_error = failure
        elif operation == "metadata":
            blob.reload_error = failure
        else:
            blob.download_error = failure
    caplog.set_level(logging.DEBUG)

    with pytest.raises(TerminalEvidenceStoreError) as exc_info:
        store.store(package)
    assert_sanitized_provider_failure(exc_info.value, caplog)


def test_gcs_evidence_store_provider_details_do_not_reach_durable_state(
    session_factory, tmp_path: Path, caplog,
) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    workflow._evidence_store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=FakeGcsClient(upload_error=FakeUnknownProviderError("provider detail should not persist")),
    )
    caplog.set_level(logging.INFO)

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="gcs-provider-detail"))
    serialized = view.model_dump_json()
    log_output = "\n".join(record.getMessage() for record in caplog.records)

    assert view.failure_reason == "publication_failed_terminal"
    assert view.publications[0].status == "FAILED_TERMINAL"
    assert view.publications[0].error_category == "evidence:terminal"
    assert "provider detail" not in serialized
    assert "provider detail" not in log_output


def test_gcs_evidence_store_rejects_unreviewed_project_or_bucket() -> None:
    with pytest.raises(TerminalEvidenceStoreError, match="project_id"):
        GcsEvidenceStore("bad_project", "bad_project-sre-cp-staging-evidence", client=FakeGcsClient())
    with pytest.raises(TerminalEvidenceStoreError, match="reviewed project boundary"):
        GcsEvidenceStore(
            "ai-operations-platform-507220",
            "other-project-sre-cp-staging-evidence",
            client=FakeGcsClient(),
        )


def test_gcs_evidence_store_rejects_unsafe_package_and_integrity_mismatch() -> None:
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=FakeGcsClient(),
    )
    safe_package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})

    with pytest.raises(EvidenceStoreError, match="unsafe content"):
        store.store(build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]}).__class__(
            payload={"message": "password=not-allowed"},
            content=b"{}",
            sha256=hashlib.sha256(b"{}").hexdigest(),
        ))
    with pytest.raises(TerminalEvidenceStoreError, match="integrity"):
        store.store(
            safe_package.__class__(
                payload=safe_package.payload,
                content=safe_package.content + b"\n",
                sha256=safe_package.sha256,
            )
        )


def test_gcs_evidence_store_unknown_upload_failure_is_terminal() -> None:
    client = FakeGcsClient(upload_error=RuntimeError("transient-looking provider failure"))
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=client,
    )
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})

    with pytest.raises(TerminalEvidenceStoreError, match="rejected"):
        store.store(package)


def test_gcs_evidence_terminal_failure_does_not_disclose_details_in_durable_state(
    session_factory, tmp_path: Path,
) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    workflow._evidence_store = TerminalSensitiveStore()

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="terminal-store"))

    assert view.failure_reason == "publication_failed_terminal"
    assert view.publications[0].status == "FAILED_TERMINAL"
    assert view.publications[0].error_category == "evidence:terminal"
    assert "provider detail" not in view.model_dump_json()


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
    assert failed.publications[0].status == "FAILED_RETRYABLE"

    publisher.fail = False
    retried = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="publication-1"))
    assert [publication.status for publication in retried.publications] == ["FAILED_RETRYABLE", "PUBLISHED"]
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


class TerminalFailingPublisher(FakePublisher):
    def __init__(self) -> None:
        super().__init__()
        self.calls = 0

    def publish(self, request):
        self.calls += 1
        raise TerminalPublicationError("terminal publication rejection")


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
    assert view.publications[0].status == "FAILED_RETRYABLE"
    assert view.publications[0].error_category == "EvidenceStoreError"
    assert view.evidence_artifacts == []


@pytest.mark.parametrize("store_factory", [lambda: MalformedStore(), lambda: UnsafeStore()])
def test_invalid_evidence_store_response_has_controlled_failure(session_factory, tmp_path: Path, store_factory) -> None:
    workflow, task = completed_workflow(session_factory, tmp_path)
    workflow._evidence_store = store_factory()

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="invalid-store"))

    assert view.failure_reason == "publication_failed_retryable"
    assert view.publications[0].status == "FAILED_RETRYABLE"
    assert view.evidence_artifacts == []


@pytest.mark.parametrize("publisher_factory", [lambda: MalformedReceiptPublisher(), lambda: UnsafeReceiptPublisher()])
def test_invalid_publisher_receipt_has_controlled_failure(session_factory, tmp_path: Path, publisher_factory) -> None:
    publisher = publisher_factory()
    workflow, task = completed_workflow(session_factory, tmp_path, publisher)

    view = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="invalid-receipt"))

    assert view.failure_reason == "publication_failed_retryable"
    assert view.publications[0].status == "FAILED_RETRYABLE"
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
    assert view.publications[0].status == "FAILED_RETRYABLE"
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
        task.task_id, publication.id, "obsolete-claim", "FAILED_RETRYABLE", None, "PublicationError", "ignored"
    )

    assert view.publications[0].status == "PUBLISHED"


def test_terminal_publication_failure_is_durable_and_cannot_be_reclaimed(session_factory, tmp_path: Path) -> None:
    publisher = TerminalFailingPublisher()
    workflow, task = completed_workflow(session_factory, tmp_path, publisher)

    failed = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="terminal-publication"))
    repeated = workflow.publish_evidence(task.task_id, EvidencePublicationRequest(idempotency_key="terminal-publication"))

    assert failed.failure_reason == "publication_failed_terminal"
    assert failed.publications[0].status == "FAILED_TERMINAL"
    assert failed.publications[0].error_category == "publication:terminal"
    assert repeated.publications[0].status == "FAILED_TERMINAL"
    assert publisher.calls == 1
    assert repeated.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert repeated.attempt is not None and repeated.attempt.state == AttemptState.SUCCEEDED


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


class TerminalSensitiveStore:
    def store(self, package):
        raise TerminalEvidenceStoreError("provider detail should not persist")


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


class FakePreconditionFailed(Exception):
    code = 412


class FakeGcsStatusError(Exception):
    def __init__(self, status_code: int) -> None:
        self.code = status_code
        super().__init__("provider detail should not leak")


class FakeUnknownProviderError(Exception):
    pass


class FakeGcsClient:
    def __init__(self, upload_error: Exception | None = None) -> None:
        self.upload_error = upload_error
        self.bucket_ref = FakeGcsBucket(self)

    def bucket(self, bucket_name: str) -> "FakeGcsBucket":
        self.bucket_ref.name = bucket_name
        return self.bucket_ref


class FakeGcsBucket:
    def __init__(self, client: FakeGcsClient) -> None:
        self.client = client
        self.name = ""
        self.blobs: dict[str, FakeGcsBlob] = {}
        self.missing_on_get = False
        self.get_error: Exception | None = None

    def blob(self, object_name: str) -> "FakeGcsBlob":
        if object_name not in self.blobs:
            self.blobs[object_name] = FakeGcsBlob(object_name, self.client)
        return self.blobs[object_name]

    def get_blob(self, object_name: str) -> "FakeGcsBlob | None":
        if self.get_error is not None:
            raise self.get_error
        if self.missing_on_get:
            return None
        return self.blobs.get(object_name)


class FakeGcsBlob:
    def __init__(self, object_name: str, client: FakeGcsClient) -> None:
        self.object_name = object_name
        self.client = client
        self.content: bytes | None = None
        self.content_type: str | None = None
        self.remote_content_type: str | None = None
        self.metadata: dict[str, str] | None = None
        self.remote_metadata: dict[str, str] | None = None
        self.remote_size = None
        self.download_content: bytes | None = None
        self.download_error: Exception | None = None
        self.reload_error: Exception | None = None
        self.ignore_range = False
        self.if_generation_match: int | None = None
        self.upload_calls = 0
        self.download_calls = 0
        self.reload_calls = 0

    def upload_from_string(
        self,
        content: bytes,
        *,
        content_type: str,
        if_generation_match: int,
    ) -> None:
        self.upload_calls += 1
        self.if_generation_match = if_generation_match
        if self.client.upload_error is not None:
            raise self.client.upload_error
        if self.content is not None and if_generation_match == 0:
            raise FakePreconditionFailed("object already exists")
        self.content = content
        self.content_type = content_type
        self.remote_content_type = content_type
        self.remote_metadata = dict(self.metadata or {})
        self.remote_size = len(content)

    def reload(self) -> None:
        self.reload_calls += 1
        if self.reload_error is not None:
            raise self.reload_error
        self.metadata = self.remote_metadata
        self.content_type = self.remote_content_type

    @property
    def size(self):
        return self.remote_size

    def download_as_bytes(self, *, start: int | None = None, end: int | None = None) -> bytes:
        self.download_calls += 1
        if self.download_error is not None:
            raise self.download_error
        if self.content is None:
            raise FileNotFoundError(self.object_name)
        content = self.download_content if self.download_content is not None else self.content
        if self.ignore_range or start is None or end is None:
            return content
        return content[start:end + 1]


def existing_gcs_artifact() -> tuple[GcsEvidenceStore, FakeGcsBlob, EvidencePackage]:
    client = FakeGcsClient()
    store = GcsEvidenceStore(
        "ai-operations-platform-507220",
        "ai-operations-platform-507220-sre-cp-staging-evidence",
        client=client,
    )
    package = build_evidence_package({"schema_version": "1.0", "entries": ["bounded"]})
    blob = client.bucket_ref.blob(gcs_evidence_object_name(package.sha256))
    blob.content = package.content
    blob.remote_content_type = EVIDENCE_CONTENT_TYPE
    blob.remote_metadata = {
        "sha256": package.sha256,
        "sanitization_status": "SANITIZED",
        "content_type": EVIDENCE_CONTENT_TYPE,
        "identity": f"sha256:{package.sha256}",
    }
    blob.remote_size = len(package.content)
    return store, blob, package


def assert_sanitized_provider_failure(exc: Exception, caplog) -> None:
    assert str(exc)
    assert "provider detail" not in str(exc)
    assert "provider detail" not in repr(exc)
    assert exc.__cause__ is None
    assert exc.__context__ is None
    assert "provider detail" not in "\n".join(record.getMessage() for record in caplog.records)
