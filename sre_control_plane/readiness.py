from __future__ import annotations

from pydantic import BaseModel, ConfigDict
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import SQLAlchemyError

from sre_control_plane.config import load_settings


class ReadinessStatus(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: str
    database: str
    migrations: str
    detail: str | None = None


def check_database_readiness(database_url: str | None = None) -> ReadinessStatus:
    url = database_url or load_settings().database_url
    engine = create_engine(url, pool_pre_ping=True)
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
            has_migration_table = inspect(connection).has_table("alembic_version")
            if not has_migration_table:
                return ReadinessStatus(
                    status="not_ready",
                    database="ok",
                    migrations="missing",
                    detail="alembic_version table is missing; run alembic upgrade head",
                )
            return ReadinessStatus(status="ok", database="ok", migrations="ok")
    except SQLAlchemyError as exc:
        return ReadinessStatus(
            status="not_ready",
            database="failed",
            migrations="unknown",
            detail=exc.__class__.__name__,
        )
    finally:
        engine.dispose()
