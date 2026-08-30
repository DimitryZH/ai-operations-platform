from __future__ import annotations

import json
import os
from dataclasses import dataclass

from sre_control_plane.executor import CapabilityReport, InvestigationExecutor
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.holmesgpt_executor import HolmesGptHttpConfig, HolmesGptHttpExecutor
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
    holmesgpt_executor: HolmesGptHttpConfig | None = None


def load_settings() -> Settings:
    repository = os.environ.get("SRE_CONTROL_PLANE_GITHUB_REPOSITORY")
    issue_number = os.environ.get("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER")
    token = os.environ.get("SRE_CONTROL_PLANE_GITHUB_TOKEN")
    configured = [value is not None for value in (repository, issue_number, token)]
    if any(configured) and not all(configured):
        raise ValueError("GitHub publication configuration is incomplete")
    github_publication = None
    if all(configured):
        try:
            github_publication = GitHubPublicationConfig(
                repository=repository,
                issue_number=int(issue_number),
                token=token,
            )
        except (TypeError, ValueError) as exc:
            raise ValueError("GitHub publication configuration is invalid") from exc

    holmes_endpoint = os.environ.get("SRE_CONTROL_PLANE_HOLMESGPT_ENDPOINT")
    holmes_local_test_mode = os.environ.get("SRE_CONTROL_PLANE_HOLMESGPT_LOCAL_TEST_MODE")
    holmes_capabilities = os.environ.get("SRE_CONTROL_PLANE_HOLMESGPT_CAPABILITIES_JSON")
    holmes_configured = [value is not None for value in (holmes_endpoint, holmes_local_test_mode, holmes_capabilities)]
    if any(holmes_configured) and not all(holmes_configured):
        raise ValueError("HolmesGPT executor configuration is incomplete")
    holmesgpt_executor = None
    if all(holmes_configured):
        holmes_configuration_invalid = False
        try:
            if holmes_local_test_mode not in {"0", "1"}:
                raise ValueError("local fixture mode must be explicit")
            holmesgpt_executor = HolmesGptHttpConfig(
                endpoint=holmes_endpoint,
                local_test_mode=holmes_local_test_mode == "1",
                capability_report=CapabilityReport.model_validate(json.loads(holmes_capabilities)),
            )
        except (TypeError, ValueError, json.JSONDecodeError):
            holmes_configuration_invalid = True
        if holmes_configuration_invalid:
            raise ValueError("HolmesGPT executor configuration is invalid")
    return Settings(
        service_name=os.environ.get("SRE_CONTROL_PLANE_SERVICE_NAME", "sre-control-plane"),
        database_url=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
        github_publication=github_publication,
        holmesgpt_executor=holmesgpt_executor,
    )


def create_publisher(settings: Settings) -> Publisher:
    if settings.github_publication is None:
        return FakePublisher()
    return GitHubPublisher(settings.github_publication)


def create_executor(settings: Settings) -> InvestigationExecutor:
    if settings.holmesgpt_executor is None:
        return FakeInvestigationExecutor()
    return HolmesGptHttpExecutor(settings.holmesgpt_executor)
