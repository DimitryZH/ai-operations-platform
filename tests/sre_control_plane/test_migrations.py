from __future__ import annotations

import os
import uuid
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import make_url

ROOT = Path(__file__).resolve().parents[2]
POSTGRES_TEST_URL = "SRE_CONTROL_PLANE_TEST_DATABASE_URL"


def test_initial_migration_creates_control_plane_tables(
    tmp_path: Path,
    monkeypatch,
) -> None:
    database_url = f"sqlite:///{tmp_path / 'control-plane.db'}"
    monkeypatch.delenv("DATABASE_URL", raising=False)
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url)

    command.upgrade(config, "head")

    engine = create_engine(database_url)
    try:
        inspector = inspect(engine)
        tables = set(inspector.get_table_names())
        retry_decision_columns = {
            column["name"] for column in inspector.get_columns("retry_decisions")
        }
        task_transition_columns = {
            column["name"] for column in inspector.get_columns("task_transitions")
        }
        publication_columns = {
            column["name"] for column in inspector.get_columns("github_publications")
        }
        with engine.connect() as connection:
            dispatch_lease_name = connection.scalar(
                text("SELECT lease_name FROM dispatch_leases WHERE lease_name = 'first_sre_dispatch'")
            )
    finally:
        engine.dispose()

    assert {
        "requests",
        "tasks",
        "attempts",
        "investigation_results",
        "task_transitions",
        "attempt_transitions",
        "capability_checks",
        "executor_invocations",
        "evidence_artifacts",
        "github_publications",
        "human_reviews",
        "retry_decisions",
        "control_locks",
        "dispatch_leases",
        "alembic_version",
    } <= tables
    assert "decision_type" in retry_decision_columns
    assert "fencing_token" in task_transition_columns
    assert {"payload_sha256", "error_category"} <= publication_columns
    assert dispatch_lease_name == "first_sre_dispatch"


def test_retry_decision_type_migration_preserves_existing_audit_rows(
    tmp_path: Path,
    monkeypatch,
) -> None:
    database_url = f"sqlite:///{tmp_path / 'existing-control-plane.db'}"
    monkeypatch.delenv("DATABASE_URL", raising=False)
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url)
    command.upgrade(config, "0003_add_retry_decisions")

    engine = create_engine(database_url)
    try:
        with engine.begin() as connection:
            connection.execute(
                text(
                    "INSERT INTO requests (id, request_id, payload, status) "
                    "VALUES (1, 'request-existing', '{}', 'ACCEPTED')"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO tasks (id, task_id, request_id, state) "
                    "VALUES (1, 'task-existing', 1, 'READY')"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO attempts (id, attempt_id, task_id, state) "
                    "VALUES (1, 'attempt-existing', 1, 'DISPATCH_FAILED')"
                )
            )
            connection.execute(
                text(
                    "INSERT INTO retry_decisions "
                    "(id, retry_id, task_id, previous_attempt_id, actor, rationale, source) "
                    "VALUES (1, 'retry-existing', 1, 1, 'operator', 'retry', 'operator_retry')"
                )
            )

        command.upgrade(config, "head")

        with engine.connect() as connection:
            decision_type = connection.scalar(
                text(
                    "SELECT decision_type FROM retry_decisions "
                    "WHERE retry_id = 'retry-existing'"
                )
            )
    finally:
        engine.dispose()

    assert decision_type == "retry"


def test_revision_ids_fit_alembic_version_column() -> None:
    revisions = []
    for path in sorted((ROOT / "alembic" / "versions").glob("*.py")):
        namespace: dict[str, object] = {}
        exec(path.read_text(), namespace)
        revisions.append(namespace["revision"])

    assert all(isinstance(revision, str) and len(revision) <= 32 for revision in revisions)


@pytest.mark.postgresql_integration
def test_postgresql_upgrade_from_initial_revision_to_head() -> None:
    database_url = os.environ.get(POSTGRES_TEST_URL)
    if database_url is None:
        pytest.skip(f"{POSTGRES_TEST_URL} is not configured")

    schema_name = f"sre_migrations_{uuid.uuid4().hex}"
    admin_engine = create_engine(database_url, pool_pre_ping=True)
    with admin_engine.begin() as connection:
        connection.execute(text(f"CREATE SCHEMA {schema_name}"))

    migration_url = make_url(database_url).update_query_dict(
        {"options": f"-csearch_path={schema_name}"}
    )
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", str(migration_url).replace("%", "%%"))
    try:
        command.upgrade(config, "0001_initial_sre_control_plane")
        command.upgrade(config, "head")
        verification_engine = create_engine(str(migration_url), pool_pre_ping=True)
        try:
            with verification_engine.connect() as connection:
                revision = connection.scalar(text("SELECT version_num FROM alembic_version"))
            columns = {column["name"] for column in inspect(verification_engine).get_columns("github_publications")}
        finally:
            verification_engine.dispose()
    finally:
        with admin_engine.begin() as connection:
            connection.execute(text(f"DROP SCHEMA {schema_name} CASCADE"))
        admin_engine.dispose()

    assert revision == "0006_evidence_publication"
    assert {"payload_sha256", "error_category"} <= columns
