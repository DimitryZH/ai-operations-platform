from __future__ import annotations

import os

import pytest

from sre_control_plane.publisher import GitHubPublicationConfig, GitHubPublisher, PublicationRequest


@pytest.mark.github_live_smoke
def test_opt_in_github_publication_smoke_reuses_marked_comment() -> None:
    """Requires an explicit opt-in and writes only to the configured dedicated Issue."""
    if os.environ.get("SRE_CONTROL_PLANE_GITHUB_LIVE_SMOKE") != "1":
        pytest.skip("set SRE_CONTROL_PLANE_GITHUB_LIVE_SMOKE=1 after explicit approval")
    repository = os.environ.get("SRE_CONTROL_PLANE_GITHUB_REPOSITORY")
    issue_number = os.environ.get("SRE_CONTROL_PLANE_GITHUB_ISSUE_NUMBER")
    token = os.environ.get("SRE_CONTROL_PLANE_GITHUB_TOKEN")
    if not repository or not issue_number or not token:
        pytest.skip("GitHub live smoke target and token are not configured")
    publisher = GitHubPublisher(
        GitHubPublicationConfig(repository=repository, issue_number=int(issue_number), token=token)
    )
    request = PublicationRequest(
        idempotency_key="approved-live-smoke-v1",
        payload_sha256="f" * 64,
        payload={
            "status": "succeeded",
            "summary": "Approved bounded GitHub publisher smoke test.",
            "findings": [{"finding_id": "smoke", "statement": "The allowlisted adapter returned a validated comment.", "evidence_ids": [], "limitations": ["No live SRE investigation was run."]}],
            "evidence_references": ["local://evidence/evidence-" + "f" * 64 + ".json"],
            "limitations": ["This is an opt-in publication adapter smoke test."],
            "human_review": "Explicit human review and closeout are required.",
        },
    )

    first = publisher.publish(request)
    repeated = publisher.publish(request)

    assert repeated.reference == first.reference
