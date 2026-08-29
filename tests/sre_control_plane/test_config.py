from __future__ import annotations

import pytest

from sre_control_plane.config import create_publisher, load_settings
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
