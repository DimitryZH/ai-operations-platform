"""Local OpenClaw status snapshot provider for the Telegram adapter scaffold."""

from __future__ import annotations

import json
from dataclasses import dataclass
from http import HTTPStatus
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

from telegram_adapter.commands import RuntimeSnapshot
from telegram_adapter.defaults import (
    DEFAULT_OPENCLAW_BASE_URL,
    DEFAULT_OPENCLAW_TIMEOUT_SECONDS,
)


LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})


@dataclass(frozen=True)
class OpenClawStatusClient:
    """Read non-secret status from a local/private OpenClaw endpoint."""

    base_url: str = DEFAULT_OPENCLAW_BASE_URL
    timeout_seconds: float = DEFAULT_OPENCLAW_TIMEOUT_SECONDS

    def __post_init__(self) -> None:
        parsed = urlparse(self.base_url)
        if parsed.scheme not in {"http", "https"}:
            raise ValueError("OpenClaw status URL must use http or https.")
        if parsed.hostname not in LOOPBACK_HOSTS:
            raise ValueError("OpenClaw status URL must use a loopback host.")

    def snapshot(self) -> RuntimeSnapshot:
        """Return a non-secret status snapshot without raising network errors."""

        health = self._get_json("/health")
        if health.ok:
            return RuntimeSnapshot(
                adapter_status="ready",
                openclaw_health="healthy",
                openclaw_status="private runtime reachable",
            )

        return RuntimeSnapshot(
            adapter_status="ready",
            openclaw_health=health.status,
            openclaw_status="private runtime not ready",
        )

    def _get_json(self, path: str) -> "StatusResult":
        url = urljoin(self.base_url.rstrip("/") + "/", path.lstrip("/"))
        request = Request(
            url,
            headers={"Accept": "application/json"},
            method="GET",
        )

        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                status_code = response.getcode()
                body = response.read(4096)
        except HTTPError as exc:
            return StatusResult(ok=False, status=f"http {exc.code}")
        except (TimeoutError, URLError, OSError) as exc:
            return StatusResult(ok=False, status=type(exc).__name__)

        if status_code != HTTPStatus.OK:
            return StatusResult(ok=False, status=f"http {status_code}")

        if not _is_truthy_health(body):
            return StatusResult(ok=False, status="unhealthy")

        return StatusResult(ok=True, status="healthy")


@dataclass(frozen=True)
class StatusResult:
    ok: bool
    status: str


def _is_truthy_health(body: bytes) -> bool:
    if not body:
        return True

    try:
        payload: Any = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return True

    if isinstance(payload, dict):
        if payload.get("ok") is False:
            return False
        if str(payload.get("status", "")).lower() in {"failed", "unhealthy"}:
            return False

    return True
