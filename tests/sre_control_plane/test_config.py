from __future__ import annotations

import pytest

from sre_control_plane.config import create_publisher, load_settings
from sre_control_plane.publisher import FakePublisher, GitHubPublisher


def test_github_publisher_is_opt_in_and_fake_is_default(monkeypatch) -> None:
    for name in ("SRE_CONTROL_PLANE_GITHUB_REPOSITORY", "SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER", "SRE_CONTROL_PLANE_GITHUB_TOKEN"):
        monkeypatch.delenv(name, raising=False)

    assert isinstance(create_publisher(load_settings()), FakePublisher)


def test_incomplete_github_configuration_fails_closed(monkeypatch) -> None:
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_REPOSITORY", "DimitryZH/ai-operations-platform")
    monkeypatch.delenv("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER", raising=False)
    monkeypatch.delenv("SRE_CONTROL_PLANE_GITHUB_TOKEN", raising=False)

    with pytest.raises(ValueError, match="requires repository"):
        load_settings()


def test_complete_github_configuration_creates_allowlisted_publisher(monkeypatch) -> None:
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_REPOSITORY", "DimitryZH/ai-operations-platform")
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER", "41")
    monkeypatch.setenv("SRE_CONTROL_PLANE_GITHUB_TOKEN", "test-token")

    assert isinstance(create_publisher(load_settings()), GitHubPublisher)
