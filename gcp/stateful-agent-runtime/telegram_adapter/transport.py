"""Fake transport dispatcher for Telegram-like updates.

This module intentionally does not call Telegram APIs, poll for updates, or send
messages. It only models how the transport hands minimal fields to the
existing adapter app.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from telegram_adapter.app import TelegramStatusAdapterApp
from telegram_adapter.commands import normalize_command
from telegram_adapter.defaults import SUPPORTED_COMMANDS
from telegram_adapter.message import InboundMessage


@dataclass(frozen=True)
class FakeTelegramOutbound:
    """Fake outbound response shape without Telegram API coupling."""

    chat_id: str
    text: str
    reply_to_message_id: str | None = None


@dataclass(frozen=True)
class TransportDiagnosticEvent:
    """Non-secret transport diagnostic event."""

    event: str
    command: str | None
    authorized: bool
    supported: bool
    malformed_reason: str | None = None


@dataclass(frozen=True)
class DispatchResult:
    """Result of dispatching a fake Telegram-like update."""

    outbound: FakeTelegramOutbound | None
    diagnostic: TransportDiagnosticEvent
    update_id: str | None = None


class FakeTelegramDispatcher:
    """Route fake Telegram-like updates to the non-enabled adapter app."""

    def __init__(self, app: TelegramStatusAdapterApp) -> None:
        self._app = app

    def dispatch(self, update: Mapping[str, Any]) -> DispatchResult:
        extracted = _extract_update(update)
        if extracted.malformed_reason is not None:
            return DispatchResult(
                outbound=None,
                diagnostic=TransportDiagnosticEvent(
                    event="telegram_adapter_malformed_update",
                    command=extracted.command,
                    authorized=False,
                    supported=False,
                    malformed_reason=extracted.malformed_reason,
                ),
                update_id=extracted.update_id,
            )

        inbound = InboundMessage.from_values(
            chat_id=extracted.chat_id or "",
            text=extracted.text,
        )
        response = self._app.handle_inbound(inbound)
        return DispatchResult(
            outbound=FakeTelegramOutbound(
                chat_id=response.chat_id,
                text=response.text,
                reply_to_message_id=extracted.message_id,
            ),
            diagnostic=TransportDiagnosticEvent(
                event="telegram_adapter_dispatched_update",
                command=response.command,
                authorized=response.authorized,
                supported=(response.command in SUPPORTED_COMMANDS),
            ),
            update_id=extracted.update_id,
        )


@dataclass(frozen=True)
class _ExtractedUpdate:
    chat_id: str | None
    text: str
    command: str | None
    message_id: str | None
    update_id: str | None
    malformed_reason: str | None = None


def _extract_update(update: Mapping[str, Any]) -> _ExtractedUpdate:
    update_id = _string_or_none(update.get("update_id"))
    message = update.get("message")
    if not isinstance(message, Mapping):
        return _ExtractedUpdate(
            chat_id=None,
            text="",
            command=None,
            message_id=None,
            update_id=update_id,
            malformed_reason="missing_message",
        )

    message_id = _string_or_none(message.get("message_id"))
    chat = message.get("chat")
    if not isinstance(chat, Mapping):
        return _ExtractedUpdate(
            chat_id=None,
            text=_safe_text(message.get("text")),
            command=normalize_command(_safe_text(message.get("text"))),
            message_id=message_id,
            update_id=update_id,
            malformed_reason="missing_chat",
        )

    chat_id = _string_or_none(chat.get("id"))
    if chat_id is None:
        return _ExtractedUpdate(
            chat_id=None,
            text=_safe_text(message.get("text")),
            command=normalize_command(_safe_text(message.get("text"))),
            message_id=message_id,
            update_id=update_id,
            malformed_reason="missing_chat_id",
        )

    raw_text = message.get("text")
    if not isinstance(raw_text, str):
        return _ExtractedUpdate(
            chat_id=chat_id,
            text="",
            command="/help",
            message_id=message_id,
            update_id=update_id,
            malformed_reason="missing_text",
        )

    return _ExtractedUpdate(
        chat_id=chat_id,
        text=raw_text,
        command=normalize_command(raw_text),
        message_id=message_id,
        update_id=update_id,
    )


def _safe_text(value: Any) -> str:
    return value if isinstance(value, str) else ""


def _string_or_none(value: Any) -> str | None:
    if value is None:
        return None
    return str(value)
