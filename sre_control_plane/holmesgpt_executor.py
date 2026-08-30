from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from threading import Event, Lock
from typing import Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from sre_control_plane.contracts import (
    MVP_GITOPS_APPLICATION,
    MVP_NAMESPACE,
    MVP_ROLLOUT,
    MVP_WORKLOAD,
    REQUIRED_CAPABILITIES,
    InvestigationResult,
    first_unsafe_string,
)
from sre_control_plane.executor import (
    AttemptStatus,
    CancelAttemptResponse,
    CapabilityReport,
    ExecutorStatus,
    StartInvestigationCommand,
    StartInvestigationResponse,
)

HOLMESGPT_EXECUTOR_ID = "executor-holmesgpt-http-prototype"
MAX_HOLMESGPT_REQUEST_BYTES = 32 * 1024
MAX_HOLMESGPT_RESPONSE_BYTES = 64 * 1024
_PRIVATE_HOST_PATTERN = re.compile(r"^[a-z0-9][a-z0-9.-]*(?:\.internal|\.local)$")
_MUTATION_DENIALS = frozenset(
    {
        "kubernetes.write",
        "rollout.mutate",
        "gitops.write",
        "deployment.write",
        "remediation.execute",
        "pull_request.merge",
        "incident.close",
        "secrets.read",
    }
)
_APPROVED_EVIDENCE_REFERENCES = frozenset(
    {
        "sre-platform://approved/slo:error_ratio_5m",
        "sre-platform://approved/slo:burn_rate_5m",
        "sre-platform://approved/ingress:online-shop-frontend",
    }
)


class HolmesGptExecutorError(RuntimeError):
    """Controlled adapter error that intentionally omits remote response content."""


class HolmesGptUnavailable(HolmesGptExecutorError):
    pass


class HolmesGptRejected(HolmesGptExecutorError):
    pass


@dataclass(frozen=True)
class HolmesGptHttpConfig:
    endpoint: str = field(repr=False)
    local_test_mode: bool = False
    timeout_seconds: int = 10
    capability_report: CapabilityReport | None = field(default=None, repr=False)

    def __post_init__(self) -> None:
        try:
            parsed = urlparse(self.endpoint)
            hostname = parsed.hostname or ""
            has_userinfo = parsed.username is not None or parsed.password is not None
            valid_path = parsed.path.rstrip("/") == ""
        except ValueError:
            raise ValueError("HolmesGPT HTTP configuration is invalid") from None
        if (
            has_userinfo
            or not valid_path
            or parsed.query
            or parsed.fragment
            or self.timeout_seconds < 1
            or self.timeout_seconds > 30
        ):
            raise ValueError("HolmesGPT HTTP configuration is invalid")
        if self.local_test_mode:
            if parsed.scheme != "http" or hostname not in {"127.0.0.1", "::1"}:
                raise ValueError("HolmesGPT local fixture endpoint is invalid")
        elif parsed.scheme != "https" or not _PRIVATE_HOST_PATTERN.fullmatch(hostname):
            raise ValueError("HolmesGPT endpoint must be a private HTTPS hostname")


@dataclass(frozen=True)
class HolmesGptHttpResponse:
    status: int
    headers: dict[str, str]
    body: bytes

    def __post_init__(self) -> None:
        object.__setattr__(self, "headers", {name.lower(): value for name, value in self.headers.items()})


class HolmesGptTransport(Protocol):
    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> HolmesGptHttpResponse: ...


@dataclass
class _StartSlot:
    semantic_identity: str
    completed: Event = field(default_factory=Event)
    response: StartInvestigationResponse | None = None
    error_type: type[HolmesGptExecutorError] | None = None


class UrllibHolmesGptTransport:
    def __init__(self, endpoint: str, timeout_seconds: int) -> None:
        self._endpoint = endpoint.rstrip("/")
        self._timeout_seconds = timeout_seconds
        self._opener = build_opener(_NoRedirectHandler())

    def request(self, method: str, path: str, headers: dict[str, str], body: bytes | None) -> HolmesGptHttpResponse:
        request = Request(self._endpoint + path, data=body, headers=headers, method=method)
        try:
            with self._opener.open(request, timeout=self._timeout_seconds) as response:  # nosec B310: endpoint is validated
                return HolmesGptHttpResponse(response.status, dict(response.headers.items()), response.read(MAX_HOLMESGPT_RESPONSE_BYTES + 1))
        except HTTPError as exc:
            return HolmesGptHttpResponse(exc.code, dict(exc.headers.items()), exc.read(MAX_HOLMESGPT_RESPONSE_BYTES + 1))
        except URLError as exc:
            raise HolmesGptUnavailable("HolmesGPT HTTP request is unavailable") from exc


class HolmesGptHttpExecutor:
    """Bounded non-streaming HolmesGPT HTTP prototype; it does not select HolmesGPT."""

    executor_id = HOLMESGPT_EXECUTOR_ID

    def __init__(self, config: HolmesGptHttpConfig, transport: HolmesGptTransport | None = None) -> None:
        self._config = config
        self._transport = transport or UrllibHolmesGptTransport(config.endpoint, config.timeout_seconds)
        self._lock = Lock()
        self._slots: dict[str, _StartSlot] = {}
        self._commands: dict[str, StartInvestigationCommand] = {}
        self._statuses: dict[str, ExecutorStatus] = {}
        self._results: dict[str, InvestigationResult] = {}

    def describe_capabilities(self) -> CapabilityReport:
        report = self._config.capability_report
        if report is None:
            raise HolmesGptRejected("HolmesGPT capability declaration is absent")
        try:
            validated = CapabilityReport.model_validate(report.model_dump(mode="json"))
        except ValidationError as exc:
            raise HolmesGptRejected("HolmesGPT capability declaration is malformed") from exc
        if capability_declaration_failure(validated, self._config.local_test_mode) is not None:
            raise HolmesGptRejected("HolmesGPT capability declaration is not fail-closed")
        return validated

    def start_investigation(self, command: StartInvestigationCommand) -> StartInvestigationResponse:
        validate_command(command)
        semantic_identity = command_semantic_identity(command)
        with self._lock:
            slot = self._slots.get(command.idempotency_key)
            if slot is None:
                slot = _StartSlot(semantic_identity=semantic_identity)
                self._slots[command.idempotency_key] = slot
                owner = True
            else:
                if slot.semantic_identity != semantic_identity:
                    raise HolmesGptRejected("HolmesGPT idempotency identity conflicts")
                owner = False

        if not owner:
            slot.completed.wait()
            return self._slot_response(slot)

        try:
            payload = holmesgpt_request_payload(command)
            raw_body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
            if len(raw_body) > MAX_HOLMESGPT_REQUEST_BYTES:
                raise HolmesGptRejected("HolmesGPT request exceeds the bounded byte limit")
            response = self._request("POST", "/api/chat", raw_body)
            result = parse_holmesgpt_analysis(response.body, command)
            start_response = StartInvestigationResponse(
                executor_id=self.executor_id,
                attempt_id=command.attempt_id,
                status=ExecutorStatus.SUCCEEDED,
                idempotency_key=command.idempotency_key,
                fencing_token=command.fencing_token,
            )
        except HolmesGptExecutorError as exc:
            with self._lock:
                slot.error_type = type(exc)
                slot.completed.set()
            raise
        except Exception as exc:
            with self._lock:
                slot.error_type = HolmesGptUnavailable
                slot.completed.set()
            raise HolmesGptUnavailable("HolmesGPT invocation failed") from exc

        with self._lock:
            self._commands[command.idempotency_key] = command
            self._statuses[command.idempotency_key] = ExecutorStatus.SUCCEEDED
            self._results[command.idempotency_key] = result
            slot.response = start_response
            slot.completed.set()
        return start_response

    @staticmethod
    def _slot_response(slot: _StartSlot) -> StartInvestigationResponse:
        if slot.error_type is not None:
            raise slot.error_type("HolmesGPT invocation did not complete")
        if slot.response is None:
            raise HolmesGptUnavailable("HolmesGPT invocation outcome is unavailable")
        return slot.response

    def get_status(self, attempt_id: str, idempotency_key: str) -> AttemptStatus:
        with self._lock:
            command = self._commands.get(idempotency_key)
            status = self._statuses.get(idempotency_key)
        if command is None or status is None or command.attempt_id != attempt_id:
            return AttemptStatus(executor_id=self.executor_id, attempt_id=attempt_id, status=ExecutorStatus.STALE)
        return AttemptStatus(executor_id=self.executor_id, attempt_id=attempt_id, status=status)

    def get_result(self, attempt_id: str, idempotency_key: str) -> InvestigationResult:
        with self._lock:
            command = self._commands.get(idempotency_key)
            result = self._results.get(idempotency_key)
        if command is None or result is None or command.attempt_id != attempt_id:
            raise HolmesGptRejected("HolmesGPT result identity is unavailable")
        return result

    def cancel_attempt(self, attempt_id: str, idempotency_key: str) -> CancelAttemptResponse:
        with self._lock:
            command = self._commands.get(idempotency_key)
            if command is not None and command.attempt_id == attempt_id:
                self._statuses[idempotency_key] = ExecutorStatus.CANCELLED
        return CancelAttemptResponse(
            executor_id=self.executor_id,
            attempt_id=attempt_id,
            status=ExecutorStatus.CANCELLED,
            partial_evidence_available=False,
        )

    def _request(self, method: str, path: str, body: bytes) -> HolmesGptHttpResponse:
        try:
            response = self._transport.request(
                method,
                path,
                {"Accept": "application/json", "Content-Type": "application/json", "User-Agent": "ai-operations-sre-control-plane"},
                body,
            )
        except HolmesGptExecutorError:
            raise
        except Exception as exc:
            raise HolmesGptUnavailable("HolmesGPT transport failed") from exc
        if len(response.body) > MAX_HOLMESGPT_RESPONSE_BYTES:
            raise HolmesGptRejected("HolmesGPT response exceeds the bounded byte limit")
        if 300 <= response.status < 400:
            raise HolmesGptRejected("HolmesGPT redirects are not allowed")
        if response.status in {408, 429} or response.status >= 500:
            raise HolmesGptUnavailable("HolmesGPT HTTP response is unavailable")
        if not 200 <= response.status < 300:
            raise HolmesGptRejected("HolmesGPT HTTP response is rejected")
        return response


class _HolmesGptChatResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    analysis: dict | str


def holmesgpt_request_payload(command: StartInvestigationCommand) -> dict:
    return {
        "ask": json.dumps(
            {
                "schema_version": "1.0",
                "request": command.request.model_dump(mode="json"),
                "task_id": command.task_id,
                "attempt_id": command.attempt_id,
                "idempotency_key": command.idempotency_key,
                "fencing_token": command.fencing_token,
                "read_only": True,
                "allowed_evidence": sorted(_APPROVED_EVIDENCE_REFERENCES),
            },
            sort_keys=True,
            separators=(",", ":"),
        ),
        "response_format": {
            "type": "json_schema",
            "json_schema": {
                "name": "first_sre_investigation_result",
                "strict": True,
                "schema": InvestigationResult.model_json_schema(),
            },
        },
        "stream": False,
        "enable_tool_approval": False,
    }


def parse_holmesgpt_analysis(raw_body: bytes, command: StartInvestigationCommand) -> InvestigationResult:
    try:
        raw_response = json.loads(raw_body)
        response = _HolmesGptChatResponse.model_validate(raw_response)
        analysis = json.loads(response.analysis) if isinstance(response.analysis, str) else response.analysis
        if not isinstance(analysis, dict) or first_unsafe_string(analysis) is not None:
            raise ValueError("unsafe analysis")
        result = InvestigationResult.model_validate(analysis)
    except (UnicodeDecodeError, json.JSONDecodeError, ValidationError, ValueError, TypeError) as exc:
        raise HolmesGptRejected("HolmesGPT response cannot be normalized") from exc
    if result.task_id != command.task_id or result.attempt_id != command.attempt_id or result.executor_id != HOLMESGPT_EXECUTOR_ID:
        raise HolmesGptRejected("HolmesGPT result identity is invalid")
    if any(item.reference not in _APPROVED_EVIDENCE_REFERENCES for item in result.evidence):
        raise HolmesGptRejected("HolmesGPT evidence reference is outside the approved scope")
    return result


def validate_command(command: StartInvestigationCommand) -> None:
    scope = command.request.scope
    if (
        command.request.constraints.read_only is not True
        or command.request.constraints.allow_mutation is not False
        or command.request.constraints.require_human_closeout is not True
        or set(command.request.requested_capabilities) != REQUIRED_CAPABILITIES
        or scope.namespace != MVP_NAMESPACE
        or scope.workload != MVP_WORKLOAD
        or scope.rollout != MVP_ROLLOUT
        or scope.gitops_application != MVP_GITOPS_APPLICATION
    ):
        raise HolmesGptRejected("HolmesGPT command is outside the approved scope")


def capability_declaration_failure(report: CapabilityReport, local_test_mode: bool) -> str | None:
    if not local_test_mode:
        return "nonfixture_recovery_not_verified"
    if set(report.declared_capabilities) != REQUIRED_CAPABILITIES:
        return "capabilities"
    if not _MUTATION_DENIALS <= set(report.denied_capabilities):
        return "mutation_denials"
    if report.target_scope != {
        "namespace": MVP_NAMESPACE,
        "workload": MVP_WORKLOAD,
        "rollout": MVP_ROLLOUT,
        "gitops_application": MVP_GITOPS_APPLICATION,
    }:
        return "scope"
    if (
        report.schema_versions != ["1.0"]
        or not report.supports_idempotent_start
        or report.supports_status_lookup
        or report.idempotency_scope != "process_local"
    ):
        return "recovery"
    if report.auth_mode != "local-fixture-no-credentials" or not report.verification_evidence:
        return "auth_or_evidence"
    return None


def command_semantic_identity(command: StartInvestigationCommand) -> str:
    return json.dumps(command.model_dump(mode="json"), sort_keys=True, separators=(",", ":"))


class _NoRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
