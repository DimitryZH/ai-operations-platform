from __future__ import annotations

import hashlib
import json
import logging
import re
from dataclasses import dataclass, field
from threading import Lock
from typing import Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

LOGGER = logging.getLogger(__name__)
GITHUB_API_URL = "https://api.github.com"
MAX_GITHUB_MARKDOWN_BYTES = 16 * 1024
MAX_GITHUB_FINDINGS = 20
MAX_GITHUB_EVIDENCE_REFERENCES = 10
MAX_GITHUB_LIMITATIONS = 20
MAX_GITHUB_COMMENT_PAGES = 3
_REPOSITORY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
_MARKER_PATTERN = re.compile(r"<!-- sre-control-plane-publication:v1:([a-f0-9]{32}):([a-f0-9]{64}) -->")
_MARKER_PREFIX = "sre-control-plane-publication:"


class PublicationError(RuntimeError):
    error_category = "publication:unknown"


class RetryablePublicationError(PublicationError):
    error_category = "publication:retryable"


class TerminalPublicationError(PublicationError):
    error_category = "publication:terminal"


@dataclass(frozen=True)
class PublicationRequest:
    idempotency_key: str
    payload_sha256: str
    payload: dict


@dataclass(frozen=True)
class PublicationReceipt:
    reference: str


class Publisher(Protocol):
    def publish(self, request: PublicationRequest) -> PublicationReceipt: ...
    def validate_receipt(self, value: object) -> PublicationReceipt: ...
    def metrics(self) -> dict[str, int]: ...


class PublicationReceiptContract(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    reference: str = Field(min_length=1, max_length=512)

    @field_validator("reference")
    @classmethod
    def validate_reference(cls, value: str) -> str:
        parsed = urlparse(value)
        if parsed.scheme != "fake" or parsed.netloc != "publication":
            raise ValueError("publication reference must use the fake://publication scheme")
        if not parsed.path.startswith("/") or len(parsed.path) != 17:
            raise ValueError("publication reference is malformed")
        if any(character not in "0123456789abcdef" for character in parsed.path[1:]):
            raise ValueError("publication reference is malformed")
        if parsed.query or parsed.fragment:
            raise ValueError("publication reference contains unsafe components")
        return value


@dataclass(frozen=True)
class GitHubPublicationConfig:
    """Configuration that deliberately keeps credentials out of validation output."""

    repository: str
    issue_number: int
    token: str = field(repr=False)
    api_url: str = GITHUB_API_URL

    def __post_init__(self) -> None:
        if (
            not isinstance(self.repository, str)
            or not _REPOSITORY_PATTERN.fullmatch(self.repository)
            or not isinstance(self.issue_number, int)
            or isinstance(self.issue_number, bool)
            or self.issue_number <= 0
            or not isinstance(self.token, str)
            or not self.token
            or self.api_url != GITHUB_API_URL
        ):
            raise ValueError("GitHub publication configuration is invalid")


class GitHubPublicationPayload(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    status: str = Field(min_length=1, max_length=32)
    summary: str = Field(min_length=1, max_length=4000)
    findings: list["GitHubFinding"] = Field(max_length=MAX_GITHUB_FINDINGS)
    evidence_references: list[str] = Field(max_length=MAX_GITHUB_EVIDENCE_REFERENCES)
    limitations: list[str] = Field(max_length=MAX_GITHUB_LIMITATIONS)
    human_review: str = Field(min_length=1, max_length=1000)

    @model_validator(mode="after")
    def validate_safe_values(self) -> "GitHubPublicationPayload":
        for text in _published_text_values(self):
            if "<!--" in text or "-->" in text or _MARKER_PREFIX in text:
                raise ValueError("GitHub publication text must not contain HTML comments or markers")
        for reference in self.evidence_references:
            parsed = urlparse(reference)
            if parsed.scheme != "local" or parsed.netloc != "evidence" or ".." in parsed.path:
                raise ValueError("evidence reference is not a bounded local artifact URI")
        return self


class GitHubFinding(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    finding_id: str = Field(min_length=1, max_length=128)
    statement: str = Field(min_length=1, max_length=2000)
    evidence_ids: list[str] = Field(max_length=20)
    limitations: list[str] = Field(max_length=20)


class GitHubCommentResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    id: int = Field(gt=0)
    html_url: str = Field(min_length=1, max_length=512)
    body: str = Field(min_length=1, max_length=MAX_GITHUB_MARKDOWN_BYTES)


@dataclass(frozen=True)
class GitHubHttpResponse:
    status: int
    headers: dict[str, str]
    body: bytes

    def __post_init__(self) -> None:
        object.__setattr__(self, "headers", {name.lower(): value for name, value in self.headers.items()})


class GitHubTransport(Protocol):
    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> GitHubHttpResponse: ...


class UrllibGitHubTransport:
    def __init__(self, api_url: str) -> None:
        self._api_url = api_url.rstrip("/")
        self._opener = build_opener(_NoRedirectHandler())

    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> GitHubHttpResponse:
        request = Request(self._api_url + path, data=body, headers=headers, method=method)
        try:
            with self._opener.open(request, timeout=10) as response:  # nosec B310: config validates the API endpoint
                return GitHubHttpResponse(response.status, dict(response.headers.items()), response.read())
        except HTTPError as exc:
            return GitHubHttpResponse(exc.code, dict(exc.headers.items()), exc.read())
        except URLError as exc:
            raise RetryablePublicationError("GitHub network request failed") from exc


class FakePublisher:
    """Deterministic local publisher. It performs no GitHub or network writes."""

    def __init__(self) -> None:
        self._references: dict[str, str] = {}

    def publish(self, request: PublicationRequest) -> PublicationReceipt:
        reference = self._references.setdefault(
            request.idempotency_key,
            "fake://publication/" + hashlib.sha256(request.payload_sha256.encode()).hexdigest()[:16],
        )
        return PublicationReceipt(reference=reference)

    def validate_receipt(self, value: object) -> PublicationReceipt:
        return validate_fake_publication_receipt(value)

    def metrics(self) -> dict[str, int]:
        return _empty_metrics()


class GitHubPublisher:
    """Fail-closed publisher for one configured repository Issue target."""

    def __init__(self, config: GitHubPublicationConfig, transport: GitHubTransport | None = None) -> None:
        self._config = config
        self._transport = transport or UrllibGitHubTransport(str(config.api_url))
        self._metrics = _empty_metrics()
        self._metrics_lock = Lock()

    def publish(self, request: PublicationRequest) -> PublicationReceipt:
        try:
            payload = GitHubPublicationPayload.model_validate(request.payload)
        except Exception as exc:
            self._terminal("GitHub publication payload violates the canonical bounded schema", exc)
        marker = publication_marker(request.idempotency_key, request.payload_sha256)
        markdown = render_github_markdown(payload, marker)
        self._increment("calls_total")
        for comment in self._list_comments():
            try:
                comment_marker = extract_marker(comment.body)
            except ValueError as exc:
                self._terminal("GitHub comment contains an ambiguous publication marker", exc)
            if comment_marker is None or comment_marker[0] != marker_key_digest(request.idempotency_key):
                continue
            if comment_marker[1] != request.payload_sha256:
                self._terminal("GitHub marker conflicts with the requested semantic payload")
            if comment.body != markdown:
                self._terminal("existing GitHub marker has unexpected content")
            self._increment("reused_total")
            self._log("github_publication_reused", idempotency_key=request.idempotency_key)
            return self._receipt_for_comment(comment)

        comment = self._decode_comment(self._request("POST", self._comments_path, {"body": markdown}))
        if comment.body != markdown:
            self._terminal("GitHub created comment body does not match the bounded request")
        self._increment("created_total")
        self._log("github_publication_created", idempotency_key=request.idempotency_key)
        return self._receipt_for_comment(comment)

    def validate_receipt(self, value: object) -> PublicationReceipt:
        if not isinstance(value, PublicationReceipt):
            raise TerminalPublicationError("GitHub publisher returned an invalid receipt type")
        self._validate_comment_url(value.reference)
        return value

    def metrics(self) -> dict[str, int]:
        with self._metrics_lock:
            return dict(self._metrics)

    @property
    def _comments_path(self) -> str:
        return f"/repos/{self._config.repository}/issues/{self._config.issue_number}/comments"

    def _list_comments(self) -> list[GitHubCommentResponse]:
        comments: list[GitHubCommentResponse] = []
        path = self._comments_path + "?per_page=100"
        for page in range(MAX_GITHUB_COMMENT_PAGES):
            response = self._request("GET", path, None)
            try:
                raw_comments = json.loads(response.body)
                if not isinstance(raw_comments, list) or len(raw_comments) > 100:
                    raise ValueError("unexpected comment list")
                comments.extend(validate_github_comment(comment) for comment in raw_comments)
                next_path = self._next_page_path(response.headers.get("link"))
            except Exception as exc:
                self._terminal("GitHub returned malformed comment-list data", exc)
            if next_path is None:
                return comments
            if page + 1 == MAX_GITHUB_COMMENT_PAGES:
                self._terminal("GitHub comment pagination exceeded its safe bound")
            path = next_path
        raise AssertionError("bounded pagination loop must return or fail")

    def _request(self, method: str, path: str, payload: dict | None) -> GitHubHttpResponse:
        body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8") if payload else None
        headers = {"Accept": "application/vnd.github+json", "Authorization": f"Bearer {self._config.token}", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "ai-operations-sre-control-plane"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        try:
            response = self._transport.request(method, path, headers, body)
        except PublicationError:
            raise
        except Exception as exc:
            self._retryable("GitHub transport request failed", exc)
        if 300 <= response.status < 400:
            self._terminal("GitHub redirect response is not allowed")
        if 200 <= response.status < 300:
            return response
        if response.status in {408, 429} or response.status >= 500 or (response.status == 403 and response.headers.get("x-ratelimit-remaining") == "0"):
            self._retryable(f"GitHub request failed with retryable status {response.status}")
        self._terminal(f"GitHub request failed with terminal status {response.status}")

    def _decode_comment(self, response: GitHubHttpResponse) -> GitHubCommentResponse:
        try:
            return validate_github_comment(json.loads(response.body))
        except Exception as exc:
            self._terminal("GitHub returned malformed comment data", exc)

    def _receipt_for_comment(self, comment: GitHubCommentResponse) -> PublicationReceipt:
        self._validate_comment_url(comment.html_url, comment.id)
        return PublicationReceipt(reference=comment.html_url)

    def _validate_comment_url(self, reference: str, comment_id: int | None = None) -> None:
        parsed = urlparse(reference)
        expected_path = f"/{self._config.repository}/issues/{self._config.issue_number}"
        if (
            parsed.scheme != "https"
            or parsed.netloc != "github.com"
            or parsed.path != expected_path
            or parsed.params
            or parsed.query
        ):
            self._terminal("GitHub comment URL is outside the allowlisted publication target")
        match = re.fullmatch(r"issuecomment-([1-9][0-9]*)", parsed.fragment)
        if match is None or (comment_id is not None and int(match.group(1)) != comment_id):
            self._terminal("GitHub comment URL is missing its comment identity")

    def _next_page_path(self, link_header: str | None) -> str | None:
        if not link_header:
            return None
        links = [item.strip() for item in link_header.split(",")]
        next_links = [item for item in links if re.search(r';\s*rel="next"$', item)]
        if len(next_links) != 1:
            raise ValueError("GitHub pagination Link header is malformed")
        match = re.fullmatch(r'<([^>]+)>;\s*rel="next"', next_links[0])
        if match is None:
            raise ValueError("GitHub pagination Link header is malformed")
        parsed = urlparse(match.group(1))
        if (
            parsed.scheme != "https"
            or parsed.netloc != "api.github.com"
            or parsed.path != self._comments_path
            or parsed.params
            or parsed.fragment
        ):
            raise ValueError("GitHub pagination target is outside the allowlist")
        query = parse_qs(parsed.query, keep_blank_values=True)
        if set(query) - {"page", "per_page"} or query.get("per_page") != ["100"]:
            raise ValueError("GitHub pagination target is malformed")
        page_values = query.get("page")
        if page_values is None or len(page_values) != 1 or not re.fullmatch(r"[1-9][0-9]*", page_values[0]):
            raise ValueError("GitHub pagination target is malformed")
        return self._comments_path + "?" + urlencode({"per_page": "100", "page": page_values[0]})

    def _increment(self, name: str) -> None:
        with self._metrics_lock:
            self._metrics[name] += 1

    def _retryable(self, message: str, cause: Exception | None = None) -> None:
        self._increment("retryable_failures_total")
        self._log("github_publication_retryable_failure")
        raise RetryablePublicationError(message) from cause

    def _terminal(self, message: str, cause: Exception | None = None) -> None:
        self._increment("terminal_failures_total")
        self._log("github_publication_terminal_failure")
        raise TerminalPublicationError(message) from cause

    def _log(self, event: str, **fields: str) -> None:
        LOGGER.info(json.dumps({"event": event, "repository": self._config.repository, "issue_number": self._config.issue_number, **fields}, sort_keys=True))


def publication_marker(idempotency_key: str, payload_sha256: str) -> str:
    if not re.fullmatch(r"[a-f0-9]{64}", payload_sha256):
        raise TerminalPublicationError("publication payload digest is malformed")
    return f"<!-- sre-control-plane-publication:v1:{marker_key_digest(idempotency_key)}:{payload_sha256} -->"


def marker_key_digest(idempotency_key: str) -> str:
    return hashlib.sha256(idempotency_key.encode("utf-8")).hexdigest()[:32]


def extract_marker(markdown: str) -> tuple[str, str] | None:
    if _MARKER_PREFIX not in markdown:
        return None
    matches = list(_MARKER_PATTERN.finditer(markdown))
    if len(matches) != 1:
        raise ValueError("publication marker is malformed")
    match = matches[0]
    if match.start() == 0 or markdown[match.start() - 1] != "\n" or match.end() != len(markdown):
        raise ValueError("publication marker is not the final canonical line")
    return match.groups()


def render_github_markdown(payload: GitHubPublicationPayload | dict, marker: str) -> str:
    if isinstance(payload, dict):
        payload = GitHubPublicationPayload.model_validate(payload)
    lines = ["## SRE Investigation Summary", "", f"**Status:** `{payload.status}`", "", "### Summary", payload.summary, "", "### Findings"]
    lines.extend(f"- {finding.statement}" for finding in payload.findings)
    lines.extend(["", "### Evidence"])
    lines.extend(f"- `{reference}`" for reference in payload.evidence_references)
    lines.extend(["", "### Limitations"])
    lines.extend(f"- {limitation}" for limitation in payload.limitations)
    lines.extend(["", "### Human Review", payload.human_review, "", marker])
    markdown = "\n".join(lines)
    if len(markdown.encode("utf-8")) > MAX_GITHUB_MARKDOWN_BYTES:
        raise TerminalPublicationError("GitHub publication Markdown exceeds its bounded byte-size limit")
    return markdown


def validate_fake_publication_receipt(value: object) -> PublicationReceipt:
    if isinstance(value, PublicationReceipt):
        raw_value = value.__dict__
    elif isinstance(value, dict):
        raw_value = value
    else:
        raise PublicationError("publisher returned an invalid response type")
    try:
        validated = PublicationReceiptContract.model_validate(raw_value)
    except Exception as exc:
        raise PublicationError("publisher returned an invalid publication receipt") from exc
    return PublicationReceipt(**validated.model_dump())


def validate_github_comment(value: object) -> GitHubCommentResponse:
    if not isinstance(value, dict):
        raise ValueError("GitHub comment response must be an object")
    return GitHubCommentResponse.model_validate(
        {field: value.get(field) for field in ("id", "html_url", "body")}
    )


def _empty_metrics() -> dict[str, int]:
    return {"calls_total": 0, "created_total": 0, "reused_total": 0, "retryable_failures_total": 0, "terminal_failures_total": 0}


class _NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _published_text_values(payload: GitHubPublicationPayload) -> list[str]:
    values = [payload.status, payload.summary, payload.human_review, *payload.evidence_references, *payload.limitations]
    for finding in payload.findings:
        values.extend([finding.finding_id, finding.statement, *finding.evidence_ids, *finding.limitations])
    return values
