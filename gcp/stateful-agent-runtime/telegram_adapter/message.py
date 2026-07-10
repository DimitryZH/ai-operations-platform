"""Message envelopes for the Telegram status-only adapter."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class InboundMessage:
    """Minimal inbound message shape used by tests and the adapter."""

    chat_id: str
    text: str

    @classmethod
    def from_values(cls, chat_id: str | int, text: str | None) -> "InboundMessage":
        return cls(chat_id=str(chat_id), text=text or "")


@dataclass(frozen=True)
class OutboundMessage:
    """Telegram-safe response envelope without Telegram API coupling."""

    chat_id: str
    text: str
    authorized: bool
    command: str | None
