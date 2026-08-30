from __future__ import annotations

import json
import os
import threading
import uuid
import hashlib
from copy import deepcopy
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import sessionmaker

from sre_control_plane.contracts import InvestigationRequest, REQUIRED_CAPABILITIES
from sre_control_plane.evidence import LocalFilesystemEvidenceStore
from sre_control_plane.executor import AttemptStatus, CapabilityReport, ExecutorStatus, StartInvestigationCommand
from sre_control_plane.fake_executor import CANONICAL_FAKE_RESULT, FakeInvestigationExecutor
from sre_control_plane.holmesgpt_executor import (
    HOLMESGPT_EXECUTOR_ID,
    HolmesGptHttpConfig,
    HolmesGptHttpExecutor,
    HolmesGptHttpResponse,
)
from sre_control_plane.publisher import (
    FakePublisher,
    GitHubHttpResponse,
    GitHubPublicationConfig,
    GitHubPublisher,
    PublicationError,
)
from sre_control_plane.persistence import (
    AttemptRecord,
    Base,
    DispatchLeaseRecord,
    ExecutorInvocationRecord,
    GitHubPublicationRecord,
    PublicationIntentRecord,
    TaskRecord,
)
from sre_control_plane.states import AttemptState, TaskState
from sre_control_plane.workflow import (
    EvidencePublicationRequest,
    SreInvestigationWorkflow,
    StaleFencingToken,
)

ROOT = Path(__file__).resolve().parents[2]
POSTGRES_TEST_URL = "SRE_CONTROL_PLANE_TEST_DATABASE_URL"


@pytest.fixture()
def postgres_session_factory():
    database_url = os.environ.get(POSTGRES_TEST_URL)
    if database_url is None:
        pytest.skip(f"{POSTGRES_TEST_URL} is not configured")

    schema_name = f"sre_dispatch_{uuid.uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True)
    with admin_engine.begin() as connection:
        connection.execute(text(f"CREATE SCHEMA {schema_name}"))

    test_engine = create_engine(
        database_url,
        connect_args={"options": f"-csearch_path={schema_name}"},
        pool_pre_ping=True,
    )
    Base.metadata.create_all(test_engine)
    try:
        yield sessionmaker(bind=test_engine, expire_on_commit=False)
    finally:
        test_engine.dispose()
        with admin_engine.begin() as connection:
            connection.execute(text(f"DROP SCHEMA {schema_name} CASCADE"))
        admin_engine.dispose()


def request_example(request_id: str) -> InvestigationRequest:
    payload = json.loads((ROOT / "examples" / "sre-investigation-request.json").read_text())
    payload["request_id"] = request_id
    payload["signal"]["fingerprint"] = request_id
    return InvestigationRequest.model_validate(payload)


@pytest.mark.postgresql_integration
def test_competing_ticks_hold_no_database_lock_during_adapter_call(
    postgres_session_factory,
) -> None:
    executor = BlockingCapabilityExecutor()
    first = SreInvestigationWorkflow(postgres_session_factory, executor)
    second = SreInvestigationWorkflow(postgres_session_factory, executor)
    task = first.submit_request(request_example("postgres-competing-ticks"))

    with ThreadPoolExecutor(max_workers=1) as pool:
        first_tick = pool.submit(first.run_dispatch_tick, "postgres-tick-one")
        assert executor.started.wait(timeout=5)
        blocked_tick = second.run_dispatch_tick("postgres-tick-two")
        executor.release.set()
        completed_tick = first_tick.result(timeout=5)

    assert completed_tick.dispatched is True
    assert blocked_tick.dispatched is False
    assert blocked_tick.reason == "active_dispatch_lease"
    with postgres_session_factory() as session:
        attempts = list(session.scalars(select(AttemptRecord)))
        persisted_task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task.task_id))
    assert len(attempts) == 1
    assert persisted_task is not None
    assert persisted_task.state == TaskState.AWAITING_HUMAN_REVIEW


@pytest.mark.postgresql_integration
def test_expired_lease_reconciles_a_confirmed_result_without_a_replacement_attempt(
    postgres_session_factory,
) -> None:
    executor = FakeInvestigationExecutor()
    workflow = SreInvestigationWorkflow(postgres_session_factory, executor)
    task, attempt_id = seed_expired_attempt(postgres_session_factory, workflow, executor)

    tick = workflow.run_dispatch_tick("postgres-reconcile-succeeded")
    view = workflow.get_task(task.task_id)

    assert tick.dispatched is False
    assert tick.reason == "reconciliation_succeeded"
    assert tick.attempt_id == attempt_id
    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.SUCCEEDED
    with postgres_session_factory() as session:
        assert len(list(session.scalars(select(AttemptRecord)))) == 1


@pytest.mark.postgresql_integration
def test_competing_reconciliation_ticks_hold_no_database_lock_during_status_lookup(
    postgres_session_factory,
) -> None:
    executor = BlockingStatusExecutor()
    first = SreInvestigationWorkflow(postgres_session_factory, executor)
    second = SreInvestigationWorkflow(postgres_session_factory, executor)
    task, attempt_id = seed_expired_attempt(postgres_session_factory, first, executor)

    with ThreadPoolExecutor(max_workers=1) as pool:
        first_tick = pool.submit(first.run_dispatch_tick, "postgres-reconcile-one")
        assert executor.started.wait(timeout=5)
        blocked_tick = second.run_dispatch_tick("postgres-reconcile-two")
        executor.release.set()
        completed_tick = first_tick.result(timeout=5)

    assert completed_tick.reason == "reconciliation_active_attempt"
    assert completed_tick.attempt_id == attempt_id
    assert blocked_tick.reason == "active_dispatch_lease"
    with postgres_session_factory() as session:
        attempts = list(session.scalars(select(AttemptRecord)))
    assert len(attempts) == 1
    assert attempts[0].state == AttemptState.RUNNING


@pytest.mark.postgresql_integration
def test_stale_fencing_token_cannot_write_a_late_outcome(postgres_session_factory) -> None:
    executor = TerminalStatusExecutor(ExecutorStatus.FAILED)
    workflow = SreInvestigationWorkflow(postgres_session_factory, executor)
    task, attempt_id = seed_expired_attempt(postgres_session_factory, workflow, executor)
    tick = workflow.run_dispatch_tick("postgres-reconcile-stale-token")

    assert tick.reason == "reconciliation_terminal"
    assert tick.fencing_token == 8

    with pytest.raises(StaleFencingToken):
        workflow._record_result_failure(
            task.task_id,
            attempt_id,
            "result_malformed:late_owner",
            "expired-owner",
            7,
        )

    view = workflow.get_task(task.task_id)
    assert view.task_state == TaskState.READY
    assert view.attempt is not None
    assert view.attempt.state == AttemptState.FAILED


@pytest.mark.postgresql_integration
def test_evidence_publication_history_is_durable_and_adapter_call_is_unlocked(
    postgres_session_factory,
    tmp_path: Path,
) -> None:
    publisher = BlockingPublisher()
    workflow = SreInvestigationWorkflow(
        postgres_session_factory,
        FakeInvestigationExecutor(),
        evidence_store=LocalFilesystemEvidenceStore(tmp_path / "evidence"),
        publisher=publisher,
    )
    task = workflow.submit_request(request_example("postgres-evidence-publication"))
    workflow.run_dispatch_tick("postgres-evidence-tick")

    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(
            workflow.publish_evidence,
            task.task_id,
            EvidencePublicationRequest(idempotency_key="postgres-publication"),
        )
        assert publisher.started.wait(timeout=5)
        with postgres_session_factory() as session:
            persisted_task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task.task_id))
            pending = session.scalar(select(ExecutorInvocationRecord).limit(1))
        assert persisted_task is not None
        assert persisted_task.state == TaskState.AWAITING_HUMAN_REVIEW
        assert pending is not None
        publisher.release.set()
        view = future.result(timeout=5)

    assert view.publications[0].status == "PUBLISHED"
    assert view.evidence_artifacts[0].sanitization_status == "SANITIZED"


@pytest.mark.postgresql_integration
def test_concurrent_publication_requests_share_a_fenced_durable_claim(
    postgres_session_factory,
    tmp_path: Path,
) -> None:
    publisher = BlockingPublisher()
    workflow = SreInvestigationWorkflow(
        postgres_session_factory,
        FakeInvestigationExecutor(),
        evidence_store=LocalFilesystemEvidenceStore(tmp_path / "concurrent-evidence"),
        publisher=publisher,
    )
    task = workflow.submit_request(request_example("postgres-concurrent-publication"))
    workflow.run_dispatch_tick("postgres-concurrent-evidence-tick")
    request = EvidencePublicationRequest(idempotency_key="postgres-concurrent-publication")

    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(workflow.publish_evidence, task.task_id, request)
        assert publisher.started.wait(timeout=5)
        second = pool.submit(workflow.publish_evidence, task.task_id, request)
        pending_view = second.result(timeout=5)
        assert pending_view.publications[0].status == "PENDING"
        publisher.release.set()
        completed_view = first.result(timeout=5)

    assert publisher.calls == 1
    assert completed_view.publications[0].status == "PUBLISHED"
    with postgres_session_factory() as session:
        publication = session.scalar(select(GitHubPublicationRecord))
        intent = session.scalar(select(PublicationIntentRecord))
    assert publication is not None and intent is not None
    stale_view = workflow._finalize_publication(
        task.task_id,
        publication.id,
        "obsolete-claim-token",
        "FAILED",
        None,
        "PublicationError",
        "ignored",
    )
    assert stale_view.publications[0].status == "PUBLISHED"
    assert intent.active_claim_token is None


@pytest.mark.postgresql_integration
def test_postgresql_github_publication_adapter_is_concurrent_and_append_only(
    postgres_session_factory,
    tmp_path: Path,
) -> None:
    transport = BlockingGitHubTransport()
    publisher = GitHubPublisher(
        GitHubPublicationConfig(
            repository="DimitryZH/ai-operations-platform",
            issue_number=41,
            token="test-token",
        ),
        transport,
    )
    workflow = SreInvestigationWorkflow(
        postgres_session_factory,
        FakeInvestigationExecutor(),
        evidence_store=LocalFilesystemEvidenceStore(tmp_path / "github-evidence"),
        publisher=publisher,
    )
    task = workflow.submit_request(request_example("postgres-github-publication"))
    workflow.run_dispatch_tick("postgres-github-evidence-tick")
    request = EvidencePublicationRequest(idempotency_key="postgres-github-publication")

    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(workflow.publish_evidence, task.task_id, request)
        assert transport.post_started.wait(timeout=5)
        second = pool.submit(workflow.publish_evidence, task.task_id, request)
        pending_view = second.result(timeout=5)
        assert pending_view.publications[0].status == "PENDING"
        transport.release_post.set()
        completed_view = first.result(timeout=5)

    assert transport.post_calls == 1
    assert completed_view.publications[0].status == "PUBLISHED"
    assert completed_view.publications[0].github_reference.endswith("#issuecomment-101")
    with postgres_session_factory() as session:
        assert len(list(session.scalars(select(GitHubPublicationRecord)))) == 1


@pytest.mark.postgresql_integration
def test_postgresql_terminal_github_publication_failure_cannot_be_retried(
    postgres_session_factory,
    tmp_path: Path,
) -> None:
    transport = TerminalGitHubTransport()
    workflow = SreInvestigationWorkflow(
        postgres_session_factory,
        FakeInvestigationExecutor(),
        evidence_store=LocalFilesystemEvidenceStore(tmp_path / "terminal-github-evidence"),
        publisher=GitHubPublisher(
            GitHubPublicationConfig(
                repository="DimitryZH/ai-operations-platform", issue_number=41, token="test-token"
            ),
            transport,
        ),
    )
    task = workflow.submit_request(request_example("postgres-terminal-github-publication"))
    workflow.run_dispatch_tick("postgres-terminal-github-evidence-tick")
    request = EvidencePublicationRequest(idempotency_key="postgres-terminal-github-publication")

    failed = workflow.publish_evidence(task.task_id, request)
    repeated = workflow.publish_evidence(task.task_id, request)

    assert failed.failure_reason == "publication_failed_terminal"
    assert failed.publications[0].status == "FAILED_TERMINAL"
    assert repeated.publications[0].status == "FAILED_TERMINAL"
    assert transport.calls == 1
    with postgres_session_factory() as session:
        assert len(list(session.scalars(select(GitHubPublicationRecord)))) == 1


@pytest.mark.postgresql_integration
def test_postgresql_retryable_publication_failure_then_success_is_append_only(
    postgres_session_factory,
    tmp_path: Path,
) -> None:
    publisher = RetryableThenSuccessfulPublisher()
    workflow = SreInvestigationWorkflow(
        postgres_session_factory,
        FakeInvestigationExecutor(),
        evidence_store=LocalFilesystemEvidenceStore(tmp_path / "retryable-github-evidence"),
        publisher=publisher,
    )
    task = workflow.submit_request(request_example("postgres-retryable-publication"))
    workflow.run_dispatch_tick("postgres-retryable-publication-tick")
    request = EvidencePublicationRequest(idempotency_key="postgres-retryable-publication")

    failed = workflow.publish_evidence(task.task_id, request)
    published = workflow.publish_evidence(task.task_id, request)

    assert failed.failure_reason == "publication_failed_retryable"
    assert [item.status for item in published.publications] == ["FAILED_RETRYABLE", "PUBLISHED"]
    assert [item.attempt_sequence for item in published.publications] == [1, 2]
    assert publisher.calls == 2


@pytest.mark.postgresql_integration
def test_postgresql_holmesgpt_http_fixture_reaches_human_review(
    postgres_session_factory,
) -> None:
    request = request_example("postgres-holmesgpt-http")
    task_id = "task-" + hashlib.sha256(request.request_id.encode()).hexdigest()[:16]
    attempt_id = f"{task_id}-a1"
    result = deepcopy(CANONICAL_FAKE_RESULT)
    result.update({
        "result_id": f"result-{attempt_id}", "task_id": task_id,
        "attempt_id": attempt_id, "executor_id": HOLMESGPT_EXECUTOR_ID,
    })
    for evidence, reference in zip(result["evidence"], [
        "sre-platform://approved/slo:error_ratio_5m",
        "sre-platform://approved/slo:burn_rate_5m",
        "sre-platform://approved/ingress:online-shop-frontend",
        "sre-platform://approved/ingress:online-shop-frontend",
    ], strict=True):
        evidence["reference"] = reference
    executor = HolmesGptHttpExecutor(
        HolmesGptHttpConfig(
            endpoint="http://127.0.0.1:18080", local_test_mode=True,
            capability_report=holmesgpt_capabilities(),
        ),
        HolmesFixtureTransport(HolmesGptHttpResponse(200, {"Content-Type": "application/json"}, json.dumps({"analysis": result}).encode("utf-8"))),
    )
    workflow = SreInvestigationWorkflow(postgres_session_factory, executor)
    task = workflow.submit_request(request)

    tick = workflow.run_dispatch_tick("postgres-holmesgpt-http")
    view = workflow.get_task(task.task_id)

    assert tick.dispatched is True
    assert view.task_state == TaskState.AWAITING_HUMAN_REVIEW
    assert view.attempt is not None and view.attempt.state == AttemptState.SUCCEEDED
    assert view.results[0].executor_id == HOLMESGPT_EXECUTOR_ID


@pytest.mark.postgresql_integration
def test_postgresql_holmesgpt_restart_reconciles_process_local_attempt_to_stale(
    postgres_session_factory,
) -> None:
    original = SreInvestigationWorkflow(postgres_session_factory, FakeInvestigationExecutor())
    task, attempt_id = seed_expired_attempt(
        postgres_session_factory,
        original,
        FakeInvestigationExecutor(),
        executor_id=HOLMESGPT_EXECUTOR_ID,
    )
    restarted = HolmesGptHttpExecutor(
        HolmesGptHttpConfig(
            endpoint="http://127.0.0.1:18080",
            local_test_mode=True,
            capability_report=holmesgpt_capabilities(),
        ),
        HolmesFixtureTransport(HolmesGptHttpResponse(200, {"Content-Type": "application/json"}, b"{}")),
    )
    workflow = SreInvestigationWorkflow(postgres_session_factory, restarted)

    tick = workflow.run_dispatch_tick("postgres-holmesgpt-restart")
    view = workflow.get_task(task.task_id)

    assert tick.reason == "reconciliation_stale"
    assert view.task_state == TaskState.READY
    assert view.attempt is not None and view.attempt.attempt_id == attempt_id
    assert view.attempt.state == AttemptState.STALE


class BlockingCapabilityExecutor(FakeInvestigationExecutor):
    def __init__(self) -> None:
        super().__init__()
        self.started = threading.Event()
        self.release = threading.Event()

    def describe_capabilities(self):
        self.started.set()
        if not self.release.wait(timeout=5):
            raise TimeoutError("test did not release fake executor")
        return super().describe_capabilities()


class BlockingPublisher(FakePublisher):
    def __init__(self) -> None:
        super().__init__()
        self.calls = 0
        self.started = threading.Event()
        self.release = threading.Event()

    def publish(self, request):
        self.calls += 1
        self.started.set()
        if not self.release.wait(timeout=5):
            raise TimeoutError("test did not release fake publisher")
        return super().publish(request)


class BlockingGitHubTransport:
    def __init__(self) -> None:
        self.post_started = threading.Event()
        self.release_post = threading.Event()
        self.post_calls = 0

    def request(self, method, path, headers, body):
        if method == "GET":
            return GitHubHttpResponse(200, {}, b"[]")
        self.post_calls += 1
        self.post_started.set()
        if not self.release_post.wait(timeout=5):
            raise TimeoutError("test did not release GitHub publisher")
        comment_body = json.loads(body)["body"]
        response = {
            "id": 101,
            "html_url": "https://github.com/DimitryZH/ai-operations-platform/issues/41#issuecomment-101",
            "body": comment_body,
        }
        return GitHubHttpResponse(201, {}, json.dumps(response).encode("utf-8"))


class TerminalGitHubTransport:
    def __init__(self) -> None:
        self.calls = 0

    def request(self, method, path, headers, body):
        self.calls += 1
        return GitHubHttpResponse(401, {}, b'{"message":"denied"}')


class RetryableThenSuccessfulPublisher(FakePublisher):
    def __init__(self) -> None:
        super().__init__()
        self.calls = 0

    def publish(self, request):
        self.calls += 1
        if self.calls == 1:
            raise PublicationError("bounded retryable failure")
        return super().publish(request)


class HolmesFixtureTransport:
    def __init__(self, response: HolmesGptHttpResponse) -> None:
        self._response = response
        self.calls = 0

    def request(self, method, path, headers, body):
        self.calls += 1
        assert method == "POST" and path == "/api/chat"
        assert "Authorization" not in headers
        return self._response


def holmesgpt_capabilities() -> CapabilityReport:
    return CapabilityReport(
        executor_id=HOLMESGPT_EXECUTOR_ID,
        schema_versions=["1.0"],
        declared_capabilities=sorted(REQUIRED_CAPABILITIES),
        denied_capabilities=[
            "kubernetes.write", "rollout.mutate", "gitops.write", "deployment.write",
            "remediation.execute", "pull_request.merge", "incident.close", "secrets.read",
        ],
        target_scope={
            "namespace": "online-shop-stage", "workload": "frontend",
            "rollout": "frontend", "gitops_application": "online-shop-stage",
        },
        auth_mode="local-fixture-no-credentials",
        verification_evidence=["deterministic local fixture; live runtime NOT TESTED"],
        supports_idempotent_start=True,
        supports_status_lookup=False,
        idempotency_scope="process_local",
    )


class BlockingStatusExecutor(FakeInvestigationExecutor):
    def __init__(self) -> None:
        super().__init__()
        self.started = threading.Event()
        self.release = threading.Event()

    def get_status(self, attempt_id: str, idempotency_key: str) -> AttemptStatus:
        self.started.set()
        if not self.release.wait(timeout=5):
            raise TimeoutError("test did not release fake executor")
        return AttemptStatus(
            executor_id=self.executor_id,
            attempt_id=attempt_id,
            status=ExecutorStatus.RUNNING,
        )


class TerminalStatusExecutor(FakeInvestigationExecutor):
    def __init__(self, status: ExecutorStatus) -> None:
        super().__init__()
        self._status = status

    def get_status(self, attempt_id: str, idempotency_key: str) -> AttemptStatus:
        return AttemptStatus(
            executor_id=self.executor_id,
            attempt_id=attempt_id,
            status=self._status,
        )


def seed_expired_attempt(
    session_factory,
    workflow,
    executor: FakeInvestigationExecutor,
    executor_id: str | None = None,
) -> tuple:
    request = request_example("postgres-reconciliation")
    task = workflow.submit_request(request)
    attempt_id = f"{task.task_id}-a1"
    executor.start_investigation(
        StartInvestigationCommand(
            request=request,
            task_id=task.task_id,
            attempt_id=attempt_id,
            idempotency_key=attempt_id,
            fencing_token=7,
        )
    )
    with session_factory.begin() as session:
        persisted_task = session.scalar(select(TaskRecord).where(TaskRecord.task_id == task.task_id))
        persisted_task.state = TaskState.RUNNING
        attempt = AttemptRecord(
            attempt_id=attempt_id,
            task_id=persisted_task.id,
            state=AttemptState.RUNNING,
            fencing_token=7,
        )
        session.add(attempt)
        session.flush()
        session.add(
            ExecutorInvocationRecord(
                attempt_id=attempt.id,
                executor_id=executor_id or executor.executor_id,
                operation="start_investigation",
                idempotency_key=attempt_id,
                fencing_token=7,
                status="RUNNING",
            )
        )
        now = datetime.now(UTC)
        session.add(
            DispatchLeaseRecord(
                lease_name="first_sre_dispatch",
                lease_owner="expired-owner",
                expires_at=now - timedelta(seconds=1),
                heartbeat_at=now - timedelta(seconds=31),
                fencing_token=7,
                task_id=persisted_task.id,
                attempt_id=attempt.id,
            )
        )
    return task, attempt_id
