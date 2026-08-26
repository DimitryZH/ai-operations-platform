from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text

ROOT = Path(__file__).resolve().parents[2]


def test_initial_migration_creates_control_plane_tables(tmp_path: Path) -> None:
    database_url = f"sqlite:///{tmp_path / 'control-plane.db'}"
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


def test_retry_decision_type_migration_preserves_existing_audit_rows(
    tmp_path: Path,
) -> None:
    database_url = f"sqlite:///{tmp_path / 'existing-control-plane.db'}"
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
