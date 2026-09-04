from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

from sre_control_plane.evidence import (
    EvidenceStore,
    EvidenceStoreError,
    GcsEvidenceStore,
    LocalFilesystemEvidenceStore,
)
from sre_control_plane.executor import CapabilityReport, InvestigationExecutor
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.holmesgpt_executor import HolmesGptHttpConfig, HolmesGptHttpExecutor
from sre_control_plane.publisher import FakePublisher, GitHubPublicationConfig, GitHubPublisher, Publisher
from sre_control_plane.sre_replay_executor import (
    SreReplayExecutor,
    SreReplayExecutorConfig,
    parse_replay_provider_declarations,
)


DEFAULT_DATABASE_URL = (
    "postgresql+psycopg://sre_control_plane:sre_control_plane"
    "@localhost:5432/sre_control_plane"
)
_POSITIVE_INTEGER_PATTERN = re.compile(r"^[1-9][0-9]*$")


@dataclass(frozen=True)
class EvidenceStoreConfig:
    mode: str = "local"
    local_root: Path = Path("var/evidence")
    gcs_project_id: str | None = None
    gcs_bucket_name: str | None = None


@dataclass(frozen=True)
class Settings:
    service_name: str = "sre-control-plane"
    database_url: str = DEFAULT_DATABASE_URL
    evidence_store: EvidenceStoreConfig = field(default_factory=EvidenceStoreConfig)
    github_publication: GitHubPublicationConfig | None = None
    holmesgpt_executor: HolmesGptHttpConfig | None = None
    sre_replay_executor: SreReplayExecutorConfig | None = None


def load_settings() -> Settings:
    github_publication = _load_github_publication_config()
    sre_replay_executor = _load_sre_replay_executor_config()

    holmes_endpoint = os.environ.get("SRE_CONTROL_PLANE_HOLMESGPT_ENDPOINT")
    holmes_local_test_mode = os.environ.get("SRE_CONTROL_PLANE_HOLMESGPT_LOCAL_TEST_MODE")
    holmes_capabilities = os.environ.get("SRE_CONTROL_PLANE_HOLMESGPT_CAPABILITIES_JSON")
    holmes_configured = [value is not None for value in (holmes_endpoint, holmes_local_test_mode, holmes_capabilities)]
    explicit_executor_mode = os.environ.get("SRE_CONTROL_PLANE_EXECUTOR")
    if explicit_executor_mode in {"fake", "sre_replay"} and any(holmes_configured):
        raise ValueError("executor configuration is ambiguous")
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

    evidence_store = _load_evidence_store_config()
    return Settings(
        service_name=os.environ.get("SRE_CONTROL_PLANE_SERVICE_NAME", "sre-control-plane"),
        database_url=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL),
        evidence_store=evidence_store,
        github_publication=github_publication,
        holmesgpt_executor=holmesgpt_executor,
        sre_replay_executor=sre_replay_executor,
    )


def _load_sre_replay_executor_config() -> SreReplayExecutorConfig | None:
    mode = os.environ.get("SRE_CONTROL_PLANE_EXECUTOR", "fake")
    scenario_id = os.environ.get("SRE_CONTROL_PLANE_SRE_REPLAY_SCENARIO_ID")
    declarations_json = os.environ.get("SRE_CONTROL_PLANE_SRE_REPLAY_PROVIDERS_JSON")
    configured = [scenario_id is not None, declarations_json is not None]
    if mode == "fake":
        if any(configured):
            raise ValueError("SRE replay executor requires explicit executor opt-in")
        return None
    if mode != "sre_replay":
        raise ValueError("executor mode is invalid")
    if not all(configured):
        raise ValueError("SRE replay executor configuration is incomplete")
    configuration_invalid = False
    configuration = None
    try:
        configuration = SreReplayExecutorConfig(
            scenario_id=scenario_id,
            provider_declarations=parse_replay_provider_declarations(declarations_json),
        )
    except (TypeError, ValueError):
        configuration_invalid = True
    if configuration_invalid or configuration is None:
        raise ValueError("SRE replay executor configuration is invalid")
    return configuration


def _load_evidence_store_config() -> EvidenceStoreConfig:
    mode = os.environ.get("SRE_CONTROL_PLANE_EVIDENCE_STORE", "local")
    if mode == "local":
        root = os.environ.get("SRE_CONTROL_PLANE_LOCAL_EVIDENCE_ROOT", "var/evidence")
        return EvidenceStoreConfig(mode="local", local_root=Path(root))
    if mode == "gcs":
        project_id = os.environ.get("SRE_CONTROL_PLANE_GCS_PROJECT_ID")
        bucket_name = os.environ.get("SRE_CONTROL_PLANE_EVIDENCE_BUCKET")
        if project_id is None or bucket_name is None:
            raise ValueError("GCS evidence store configuration is incomplete")
        return EvidenceStoreConfig(
            mode="gcs",
            gcs_project_id=project_id,
            gcs_bucket_name=bucket_name,
        )
    raise ValueError("evidence store mode is invalid")


def _load_github_publication_config() -> GitHubPublicationConfig | None:
    mode = os.environ.get("SRE_CONTROL_PLANE_PUBLISHER", "fake")
    github_env_names = (
        "SRE_CONTROL_PLANE_GITHUB_REPOSITORY",
        "SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER",
        "SRE_CONTROL_PLANE_GITHUB_ALLOWED_REPOSITORY",
        "SRE_CONTROL_PLANE_GITHUB_ALLOWED_ISSUE_NUMBER",
        "SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_NAME",
        "SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_VERSION",
        "SRE_CONTROL_PLANE_GITHUB_TOKEN",
    )
    github_values = {name: os.environ.get(name) for name in github_env_names}
    configured = [value is not None for value in github_values.values()]
    if mode == "fake":
        if any(configured):
            raise ValueError("GitHub publication requires explicit publisher opt-in")
        return None
    if mode != "github":
        raise ValueError("publisher mode is invalid")
    if not all(configured):
        raise ValueError("GitHub publication configuration is incomplete")
    issue_number = _parse_positive_int(github_values["SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER"])
    allowed_issue_number = _parse_positive_int(github_values["SRE_CONTROL_PLANE_GITHUB_ALLOWED_ISSUE_NUMBER"])
    if issue_number is None or allowed_issue_number is None:
        raise ValueError("GitHub publication configuration is invalid")
    token = github_values["SRE_CONTROL_PLANE_GITHUB_TOKEN"].strip()
    if not token or "\n" in token or "\r" in token:
        raise ValueError("GitHub publication configuration is invalid")
    try:
        return GitHubPublicationConfig(
            repository=github_values["SRE_CONTROL_PLANE_GITHUB_REPOSITORY"],
            issue_number=issue_number,
            token=token,
            allowed_repository=github_values["SRE_CONTROL_PLANE_GITHUB_ALLOWED_REPOSITORY"],
            allowed_issue_number=allowed_issue_number,
            credential_secret_name=github_values["SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_NAME"],
            credential_secret_version=github_values["SRE_CONTROL_PLANE_GITHUB_CREDENTIAL_SECRET_VERSION"],
        )
    except (TypeError, ValueError):
        raise ValueError("GitHub publication configuration is invalid") from None


def _parse_positive_int(value: str | None) -> int | None:
    if value is None or _POSITIVE_INTEGER_PATTERN.fullmatch(value) is None:
        return None
    return int(value)


def create_evidence_store(settings: Settings) -> EvidenceStore:
    if settings.evidence_store.mode == "local":
        return LocalFilesystemEvidenceStore(settings.evidence_store.local_root)
    if settings.evidence_store.mode == "gcs":
        if settings.evidence_store.gcs_project_id is None or settings.evidence_store.gcs_bucket_name is None:
            raise ValueError("GCS evidence store configuration is incomplete")
        try:
            return GcsEvidenceStore(
                project_id=settings.evidence_store.gcs_project_id,
                bucket_name=settings.evidence_store.gcs_bucket_name,
            )
        except EvidenceStoreError as exc:
            raise ValueError(str(exc)) from exc
    raise ValueError("evidence store mode is invalid")


def create_publisher(settings: Settings) -> Publisher:
    if settings.github_publication is None:
        return FakePublisher()
    return GitHubPublisher(settings.github_publication)


def create_executor(settings: Settings) -> InvestigationExecutor:
    if settings.sre_replay_executor is not None:
        return SreReplayExecutor(settings.sre_replay_executor)
    if settings.holmesgpt_executor is None:
        return FakeInvestigationExecutor()
    return HolmesGptHttpExecutor(settings.holmesgpt_executor)
