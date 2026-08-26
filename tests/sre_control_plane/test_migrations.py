from __future__ import annotations

from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

ROOT = Path(__file__).resolve().parents[2]


def test_initial_migration_creates_control_plane_tables(tmp_path: Path) -> None:
    database_url = f"sqlite:///{tmp_path / 'control-plane.db'}"
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url)

    command.upgrade(config, "head")

    engine = create_engine(database_url)
    try:
        tables = set(inspect(engine).get_table_names())
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
