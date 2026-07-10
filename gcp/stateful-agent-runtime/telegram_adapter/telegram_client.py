"""Telegram Bot API client for status-only polling.

This module keeps token material out of reprs and diagnostics. Runtime startup
is controlled by the Terraform enable flag and systemd unit.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from typing import Any, Protocol
from urllib.request import Request, urlopen


class TelegramApiError(RuntimeError):
    """Safe Telegram API error that does not include token or message payloads."""

    def __init__(
        self,
        message: str,
        *,
        method: str,
        reason: str,
        error_code: int | None = None,
    ) -> None:
        super().__init__(message)
        self.method = method
        self.reason = reason
        self.error_code = error_code

    def __repr__(self) -> str:
        return (
            "TelegramApiError("
            f"method={self.method!r}, "
            f"reason={self.reason!r}, "
            f"error_code={self.error_code!r})"
        )


class TelegramHttpTransport(Protocol):
    """Transport interface for Telegram HTTP wiring."""

    def post_json(
        self,
        *,
        token: str,
        method: str,
        payload: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        """Post a Telegram method request and return the decoded JSON body."""


@dataclass(frozen=True)
class FakeTelegramHttpRequest:
    """Recorded fake request shape without token storage."""

    method: str
    payload: Mapping[str, Any]


@dataclass
class FakeTelegramHttpTransport:
    """Fake test transport that records sanitized request shapes only."""

    responses: list[Mapping[str, Any]] = field(default_factory=list)
    exception: Exception | None = None
    requests: list[FakeTelegramHttpRequest] = field(default_factory=list)

    def post_json(
        self,
        *,
        token: str,
        method: str,
        payload: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        if self.exception is not None:
            raise self.exception

        self.requests.append(
            FakeTelegramHttpRequest(method=method, payload=dict(payload))
        )
        if self.responses:
            return self.responses.pop(0)
        return {"ok": True, "result": []}


class UrllibTelegramHttpTransport:
    """Explicit-only Telegram HTTP transport using the standard library."""

    def __init__(
        self,
        *,
        post_json: Callable[
            [str, bytes, Mapping[str, str], float],
            bytes,
        ]
        | None = None,
        timeout_seconds: float = 30.0,
        base_url: str = "https://api.telegram.org",
    ) -> None:
        self._post_json = post_json or _urllib_post_json
        self._timeout_seconds = timeout_seconds
        self._base_url = base_url.rstrip("/")

    def __repr__(self) -> str:
        return (
            "UrllibTelegramHttpTransport("
            "base_url=<redacted>, "
            f"timeout_seconds={self._timeout_seconds!r})"
        )

    def post_json(
        self,
        *,
        token: str,
        method: str,
        payload: Mapping[str, Any],
    ) -> Mapping[str, Any]:
        url = f"{self._base_url}/bot{token}/{method}"
        body = json.dumps(dict(payload)).encode("utf-8")
        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

        http_failed = False
        try:
            raw_response = self._post_json(
                url,
                body,
                headers,
                self._timeout_seconds,
            )
        except Exception:
            http_failed = True

        if http_failed:
            raise TelegramApiError(
                "Telegram API HTTP transport failed",
                method=method,
                reason="http_error",
            )

        invalid_json = False
        try:
            response = json.loads(raw_response.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            invalid_json = True

        if invalid_json:
            raise TelegramApiError(
                "Telegram API returned invalid JSON",
                method=method,
                reason="invalid_json",
            )

        if not isinstance(response, Mapping):
            raise TelegramApiError(
                "Telegram API returned an invalid response",
                method=method,
                reason="invalid_response",
            )

        return response


def _urllib_post_json(
    url: str,
    body: bytes,
    headers: Mapping[str, str],
    timeout_seconds: float,
) -> bytes:
    request = Request(
        url,
        data=body,
        headers=dict(headers),
        method="POST",
    )
    with urlopen(request, timeout=timeout_seconds) as response:
        return response.read(1024 * 1024)


class TelegramBotApiClient:
    """Small client with injected HTTP transport only."""

    def __init__(
        self,
        *,
        token: str,
        transport: TelegramHttpTransport,
        default_timeout_seconds: int = 30,
    ) -> None:
        self._token = token
        self._transport = transport
        self._default_timeout_seconds = default_timeout_seconds

    def __repr__(self) -> str:
        return (
            "TelegramBotApiClient("
            "token=<redacted>, "
            f"default_timeout_seconds={self._default_timeout_seconds!r})"
        )

    def get_updates(
        self,
        *,
        offset: int | None = None,
        timeout_seconds: int | None = None,
    ) -> Any:
        payload: dict[str, Any] = {
            "timeout": (
                self._default_timeout_seconds
                if timeout_seconds is None
                else timeout_seconds
            )
        }
        if offset is not None:
            payload["offset"] = offset
        return self._call("getUpdates", payload)

    def send_message(
        self,
        *,
        chat_id: str | int,
        text: str,
        reply_to_message_id: str | int | None = None,
    ) -> Any:
        payload: dict[str, Any] = {
            "chat_id": chat_id,
            "text": text,
        }
        if reply_to_message_id is not None:
            payload["reply_to_message_id"] = reply_to_message_id
        return self._call("sendMessage", payload)

    def _call(self, method: str, payload: Mapping[str, Any]) -> Any:
        transport_failed = False
        try:
            response = self._transport.post_json(
                token=self._token,
                method=method,
                payload=payload,
            )
        except Exception:
            transport_failed = True

        if transport_failed:
            raise TelegramApiError(
                "Telegram API transport failed",
                method=method,
                reason="transport_error",
            )

        if not isinstance(response, Mapping):
            raise TelegramApiError(
                "Telegram API returned an invalid response",
                method=method,
                reason="invalid_response",
            )

        if response.get("ok") is not True:
            error_code = response.get("error_code")
            safe_error_code = error_code if isinstance(error_code, int) else None
            raise TelegramApiError(
                "Telegram API returned ok=false",
                method=method,
                reason="api_not_ok",
                error_code=safe_error_code,
            )

        return response.get("result")
