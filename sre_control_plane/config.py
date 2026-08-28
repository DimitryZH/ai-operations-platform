from __future__ import annotations

import os
from dataclasses import dataclass

from sre_control_plane.publisher import FakePublisher, GitHubPublicationConfig, GitHubPublisher, Publisher


DEFAULT_DATABASE_URL = (
    "postgresql+psycopg://sre_control_plane:sre_control_plane"
    "@localhost:5432/sre_control_plane"
)


@dataclass(frozen=True)
class Settings:
    service_name: str = "sre-control-plane"
    database_url: str = DEFAULT_DATABASE_URL
    github_publication: GitHubPublicationConfig | None = None


def load_settings() -> Settings:
    repository = os.environ.get("SRE_CONTROL_PLANE_GITHUB_REPOSITORY")
    issue_number = os.environ.get("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER")
    token = os.environ.get("SRE_CONTROL_PLANE_GITHUB_TOKEN")
    configured = [value is not None for value in (repository, issue_number, token)]
    if any(configured) and not all(configured):
        raise ValueError("GitHub publication requires repository, Issue number, and token together")
    github_publication = None
    if all(configured):
        github_publication = GitHubPublicationConfig(
            repository=repository,
            issue_number=int(issue_number),
            token=token,
        )
    return Settings(
        service_name=os.environ.get("SRE_CONTROL_PLANE_SERVICE_NAME", "sre-control-plane"),
        database_url=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
        github_publication=github_publication,
    )


def create_publisher(settings: Settings) -> Publisher:
    if settings.github_publication is None:
        return FakePublisher()
    return GitHubPublisher(settings.github_publication)
