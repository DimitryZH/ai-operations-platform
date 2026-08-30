from __future__ import annotations

import json

import pytest

from sre_control_plane.config import create_executor, create_publisher, load_settings
from sre_control_plane.fake_executor import FakeInvestigationExecutor
from sre_control_plane.holmesgpt_executor import HOLMESGPT_EXECUTOR_ID, HolmesGptHttpExecutor
from sre_control_plane.publisher import FakePublisher, GitHubPublisher


def test_github_publisher_is_opt_in_and_fake_is_default(monkeypatch) -> None:
    for name in ("SRE_CONTROL_PLANE_GITHUB_REPOSITORY", "SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER", "SRE_CONTROL_PLANE_GITHUB_TOKEN"):
        monkeypatch.delenv(name, raising=False)

    assert isinstance(create_publisher(load_settings()), FakePublisher)


def test_incomplete_github_configuration_fails_closed_without_token_disclosure(monkeypatch, caplog) -> None:
    secret = "recognizable-secret-token"
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_REPOSITORY", "DimitryZH/ai-operations-platform")
    monkeypatch.delenv("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER", raising=False)
    monkeypatch.delenv("SRE_CONTROL_PLANE_GITHUB_TOKEN", raising=False)

    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_TOKEN", secret)
    with pytest.raises(ValueError) as exc_info:
        load_settings()
    assert secret not in str(exc_info.value)
    assert secret not in caplog.text


def test_complete_github_configuration_creates_allowlisted_publisher(monkeypatch) -> None:
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_REPOSITORY", "DimitryZH/ai-operations-platform")
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER", "41")
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_TOKEN", "test-token")

    assert isinstance(create_publisher(load_settings()), GitHubPublisher)


def test_invalid_github_configuration_never_exposes_token(monkeypatch, caplog) -> None:
    secret = "recognizable-secret-token"
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_REPOSITORY", "not a repository")
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER", "41")
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_TOKEN", secret)

    with pytest.raises(ValueError) as exc_info:
        load_settings()

    assert secret not in str(exc_info.value)
    assert secret not in caplog.text


def test_holmesgpt_executor_is_opt_in_and_fake_is_default(monkeypatch) -> None:
    for name in (
        "SRE_CONTROL_PLANE_HOLMESGPT_ENDPOINT",
        "SRE_CONTROL_PLANE_HOLMESGPT_LOCAL_TEST_MODE",
        "SRE_CONTROL_PLANE_HOLMESGPT_CAPABILITIES_JSON",
    ):
        monkeypatch.delenv(name, raising=False)
    assert isinstance(create_executor(load_settings()), FakeInvestigationExecutor)


def test_holmesgpt_executor_configuration_is_complete_and_local_only(monkeypatch) -> None:
    monkeypatch.setenv("SRE_CONTROL_PLANE_HOLMESGPT_ENDPOINT", "http://127.0.0.1:18080")
    monkeypatch.delenv("SRE_CONTROL_PLANE_HOLMESGPT_LOCAL_TEST_MODE", raising=False)
    monkeypatch.delenv("SRE_CONTROL_PLANE_HOLMESGPT_CAPABILITIES_JSON", raising=False)
    with pytest.raises(ValueError, match="incomplete"):
        load_settings()

    capability_payload = {
        "executor_id": HOLMESGPT_EXECUTOR_ID,
        "schema_versions": ["1.0"],
        "declared_capabilities": ["kubernetes.read", "prometheus.query", "rollout.read", "gitops.read", "logs.read", "investigation.report"],
        "denied_capabilities": ["kubernetes.write", "rollout.mutate", "gitops.write", "deployment.write", "remediation.execute", "pull_request.merge", "incident.close", "secrets.read"],
        "target_scope": {"namespace": "online-shop-stage", "workload": "frontend", "rollout": "frontend", "gitops_application": "online-shop-stage"},
        "auth_mode": "local-fixture-no-credentials",
        "verification_evidence": ["deterministic local fixture; live runtime NOT TESTED"],
        "supports_idempotent_start": True,
        "supports_status_lookup": False,
        "idempotency_scope": "process_local",
    }
    monkeypatch.setenv("SRE_CONTROL_PLANE_HOLMESGPT_LOCAL_TEST_MODE", "1")
    monkeypatch.setenv("SRE_CONTROL_PLANE_HOLMESGPT_CAPABILITIES_JSON", json.dumps(capability_payload))
    assert isinstance(create_executor(load_settings()), HolmesGptHttpExecutor)
