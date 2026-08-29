from __future__ import annotations

import json
import threading
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from sre_control_plane.publisher import (
    GitHubHttpResponse,
    GitHubPublicationConfig,
    GitHubPublisher,
    PublicationRequest,
    RetryablePublicationError,
    TerminalPublicationError,
    UrllibGitHubTransport,
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


@pytest.mark.parametrize(
    "url",
    [
        "https://github.com/DimitryZH/ai-operations-platform/issues/410#issuecomment-101",
        "https://github.com/other/repository/issues/41#issuecomment-101",
        "https://github.com/DimitryZH/ai-operations-platform/issues/41",
        "https://github.com/DimitryZH/ai-operations-platform/issues/41#issuecomment-101-extra",
        "https://github.com/DimitryZH/ai-operations-platform/issues/41#issuecomment-102",
    ],
)
def test_comment_url_requires_exact_target_and_identity(url: str) -> None:
    request = publication_request()
    malformed = comment_payload(request)
    malformed["html_url"] = url
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), QueueTransport([response(200, []), response(201, malformed)])).publish(request)


@pytest.mark.parametrize("status", [301, 302, 307, 308])
def test_redirects_fail_closed_without_following_or_second_request(status: int) -> None:
    transport = QueueTransport([response(status, {"message": "redirect"}, {"Location": "https://external.example/comments"})])
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), transport).publish(publication_request())
    assert len(transport.calls) == 1
    assert transport.calls[0][2]["Authorization"] == "Bearer test-token"


def test_terminal_failure_metrics_are_not_reported_as_retryable() -> None:
    publisher = GitHubPublisher(config(), QueueTransport([response(401, {"message": "denied"})]))
    with pytest.raises(TerminalPublicationError):
        publisher.publish(publication_request())
    assert publisher.metrics()["terminal_failures_total"] == 1
    assert publisher.metrics()["retryable_failures_total"] == 0


def test_marker_on_second_safe_page_is_reused_without_post() -> None:
    request = publication_request()
    next_link = "<https://api.github.com/repos/DimitryZH/ai-operations-platform/issues/41/comments?per_page=100&page=2>; rel=\"next\""
    transport = QueueTransport([
        response(200, [], {"Link": next_link}),
        response(200, [comment_payload(request)]),
    ])

    GitHubPublisher(config(), transport).publish(request)

    assert [call[:2] for call in transport.calls] == [
        ("GET", "/repos/DimitryZH/ai-operations-platform/issues/41/comments?per_page=100"),
        ("GET", "/repos/DimitryZH/ai-operations-platform/issues/41/comments?per_page=100&page=2"),
    ]


@pytest.mark.parametrize("header_name", ["link", "LiNk", "LINK"])
def test_marker_on_second_page_is_reused_for_case_insensitive_link_header(header_name: str) -> None:
    request = publication_request()
    next_link = "<https://api.github.com/repos/DimitryZH/ai-operations-platform/issues/41/comments?per_page=100&page=2>; rel=\"next\""
    transport = QueueTransport([
        response(200, [], {header_name: next_link}),
        response(200, [comment_payload(request)]),
    ])

    GitHubPublisher(config(), transport).publish(request)

    assert len(transport.calls) == 2


@pytest.mark.parametrize("header_name", ["x-ratelimit-remaining", "X-RateLimit-Remaining", "X-RaTeLiMiT-ReMaInInG"])
def test_rate_limit_header_is_case_insensitive(header_name: str) -> None:
    transport = QueueTransport([response(403, {"message": "rate limited"}, {header_name: "0"})])
    with pytest.raises(RetryablePublicationError):
        GitHubPublisher(config(), transport).publish(publication_request())


@pytest.mark.parametrize(
    "link",
    [
        "<https://external.example/comments?page=2>; rel=\"next\"",
        "<https://api.github.com/repos/DimitryZH/ai-operations-platform/issues/410/comments?per_page=100&page=2>; rel=\"next\"",
        "not-a-link",
    ],
)
def test_unsafe_pagination_link_fails_closed_without_post(link: str) -> None:
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), QueueTransport([response(200, [], {"Link": link})])).publish(publication_request())


def test_pagination_bound_fails_closed_without_post() -> None:
    link = "<https://api.github.com/repos/DimitryZH/ai-operations-platform/issues/41/comments?per_page=100&page={}>; rel=\"next\""
    transport = QueueTransport([
        response(200, [], {"Link": link.format(2)}),
        response(200, [], {"Link": link.format(3)}),
        response(200, [], {"Link": link.format(4)}),
    ])
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), transport).publish(publication_request())
    assert len(transport.calls) == 3


@pytest.mark.parametrize(
    "mutate",
    [
        lambda payload: payload.__setitem__("summary", "safe <!-- injected -->"),
        lambda payload: payload["findings"][0].__setitem__("statement", "safe <!-- injected -->"),
        lambda payload: payload.__setitem__("limitations", ["safe <!-- injected -->"]),
        lambda payload: payload.__setitem__("human_review", "safe <!-- injected -->"),
    ],
)
def test_marker_injection_in_payload_fails_closed_without_network(mutate) -> None:
    request = publication_request()
    mutate(request.payload)
    transport = QueueTransport([])
    with pytest.raises(TerminalPublicationError):
        GitHubPublisher(config(), transport).publish(request)
    assert transport.calls == []


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


def response(status: int, payload: object, headers: dict[str, str] | None = None) -> GitHubHttpResponse:
    return GitHubHttpResponse(status=status, headers=headers or {}, body=json.dumps(payload).encode("utf-8"))


class RaisingTransport:
    def request(self, method, path, headers, body):
        raise OSError("test network unavailable")


@pytest.mark.parametrize("status", [301, 302, 307, 308])
def test_urllib_transport_does_not_follow_redirect_or_forward_authorization(status: int) -> None:
    received_authorization: list[str | None] = []

    class TargetHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            received_authorization.append(self.headers.get("Authorization"))
            self.send_response(200)
            self.end_headers()

        def log_message(self, format, *args):
            return

    with local_server(TargetHandler) as target:
        target_url = f"http://127.0.0.1:{target.server_port}/target"

        class RedirectHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(status)
                self.send_header("Location", target_url)
                self.end_headers()

            def log_message(self, format, *args):
                return

        with local_server(RedirectHandler) as redirector:
            transport = UrllibGitHubTransport(f"http://127.0.0.1:{redirector.server_port}")
            response_value = transport.request("GET", "/start", {"Authorization": "Bearer recognizable-test-token"}, None)

    assert response_value.status == status
    assert received_authorization == []


@contextmanager
def local_server(handler):
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()
