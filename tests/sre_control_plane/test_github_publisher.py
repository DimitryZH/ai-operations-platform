from __future__ import annotations

import json

import pytest

from sre_control_plane.publisher import (
    GitHubHttpResponse,
    GitHubPublicationConfig,
    GitHubPublisher,
    PublicationRequest,
    RetryablePublicationError,
    TerminalPublicationError,
    publication_marker,
    render_github_markdown,
)


def publication_request() -> PublicationRequest:
    return PublicationRequest(
        idempotency_key="publication-key-1",
        payload_sha256="a" * 64,
        payload={
            "status": "succeeded",
            "summary": "Bounded fake investigation summary.",
            "findings": [{"finding_id": "finding-1", "statement": "A bounded finding.", "evidence_ids": ["evidence-1"], "limitations": ["Fake evidence only."]}],
            "evidence_references": ["local://evidence/evidence-" + "b" * 64 + ".json"],
            "limitations": ["No live systems were accessed."],
            "human_review": "Explicit human review and closeout are required.",
        },
    )


def config() -> GitHubPublicationConfig:
    return GitHubPublicationConfig(repository="DimitryZH/ai-operations-platform", issue_number=41, token="test-token")


def comment_payload(request: PublicationRequest, comment_id: int = 101) -> dict:
    marker = publication_marker(request.idempotency_key, request.payload_sha256)
    body = render_github_markdown(request.payload, marker)
    return {"id": comment_id, "html_url": f"https://github.com/DimitryZH/ai-operations-platform/issues/41#issuecomment-{comment_id}", "body": body, "user": {"login": "ignored"}}


def test_allowlisted_adapter_creates_one_bounded_marked_comment() -> None:
    request = publication_request()
    transport = QueueTransport([
        response(200, []),
        response(201, comment_payload(request)),
    ])
    publisher = GitHubPublisher(config(), transport)

    receipt = publisher.publish(request)

    assert receipt.reference.endswith("#issuecomment-101")
    assert [call[0:2] for call in transport.calls] == [
        ("GET", "/repos/DimitryZH/ai-operations-platform/issues/41/comments?per_page=100"),
        ("POST", "/repos/DimitryZH/ai-operations-platform/issues/41/comments"),
    ]
    created_body = json.loads(transport.calls[1][3])["body"]
    assert publication_marker(request.idempotency_key, request.payload_sha256) in created_body
    assert len(created_body.encode("utf-8")) <= 16 * 1024
    assert publisher.metrics()["created_total"] == 1


def test_existing_matching_marker_is_reused_without_post() -> None:
    request = publication_request()
    transport = QueueTransport([response(200, [comment_payload(request)])])

    receipt = GitHubPublisher(config(), transport).publish(request)

    assert receipt.reference.endswith("#issuecomment-101")
    assert len(transport.calls) == 1


def test_conflicting_marker_fails_closed_without_write() -> None:
    request = publication_request()
    conflicting = comment_payload(request)
    conflicting["body"] = conflicting["body"].replace("a" * 64, "c" * 64)
    transport = QueueTransport([response(200, [conflicting])])

    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), transport).publish(request)

    assert len(transport.calls) == 1


@pytest.mark.parametrize("status", [401, 403, 404, 422])
def test_auth_authorization_and_validation_failures_are_terminal(status: int) -> None:
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), QueueTransport([response(status, {"message": "blocked"})])).publish(publication_request())


@pytest.mark.parametrize("status", [429, 500])
def test_rate_limit_and_server_failures_are_retryable(status: int) -> None:
    with pytest.raises(RetryablePublicationError):
        GitHubPublisher(config(), QueueTransport([response(status, {"message": "retry"})])).publish(publication_request())


def test_malformed_or_wrong_target_comment_fails_closed() -> None:
    request = publication_request()
    malformed = comment_payload(request)
    malformed["html_url"] = "https://github.com/other/repository/issues/1#issuecomment-101"
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), QueueTransport([response(200, []), response(201, malformed)])).publish(request)


def test_invalid_payload_and_transport_error_have_explicit_failure_classes() -> None:
    request = publication_request()
    request.payload["evidence_references"] = ["https://unsafe.example/evidence"]
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), QueueTransport([])).publish(request)

    with pytest.raises(RetryablePublicationError):
        GitHubPublisher(config(), RaisingTransport()).publish(publication_request())


class QueueTransport:
    def __init__(self, responses: list[GitHubHttpResponse]) -> None:
        self._responses = responses
        self.calls: list[tuple[str, str, dict[str, str], bytes | None]] = []

    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> GitHubHttpResponse:
        self.calls.append((method, path, headers, body))
        return self._responses.pop(0)


def response(status: int, payload: object) -> GitHubHttpResponse:
    return GitHubHttpResponse(status=status, headers={}, body=json.dumps(payload).encode("utf-8"))


class RaisingTransport:
    def request(self, method, path, headers, body):
        raise OSError("test network unavailable")
