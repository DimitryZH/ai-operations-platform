from __future__ import annotations

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from sre_control_plane.config import load_settings


def create_database_engine(database_url: str | None = None) -> Engine:
    return create_engine(database_url or load_settings().database_url, pool_pre_ping=True)


def create_session_factory(database_url: str | None = None) -> sessionmaker[Session]:
    return sessionmaker(
        bind=create_database_engine(database_url),
        expire_on_commit=False,
        autoflush=True,
    )
