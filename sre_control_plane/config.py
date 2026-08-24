from __future__ import annotations

import os
from dataclasses import dataclass


DEFAULT_DATABASE_URL = (
    "postgresql+psycopg://sre_control_plane:sre_control_plane"
    "@localhost:5432/sre_control_plane"
)


@dataclass(frozen=True)
class Settings:
    service_name: str = "sre-control-plane"
    database_url: str = DEFAULT_DATABASE_URL


def load_settings() -> Settings:
    return Settings(
        service_name=os.environ.get("SRE_CONTROL_PLANE_SERVICE_NAME", "sre-control-plane"),
        database_url=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
    )
