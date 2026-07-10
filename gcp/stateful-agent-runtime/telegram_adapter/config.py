"""Configuration model for the Telegram status-only adapter."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from telegram_adapter.defaults import (
    DEFAULT_OPENCLAW_BASE_URL,
    DEFAULT_OPENCLAW_TIMEOUT_SECONDS,
)
from telegram_adapter.status_snapshot import (
    OpenClawStatusClient,
)


@dataclass(frozen=True)
class TelegramAdapterConfig:
    """Validated non-secret adapter configuration."""

    allowed_chat_ids: frozenset[str]
    openclaw_base_url: str = DEFAULT_OPENCLAW_BASE_URL
    openclaw_timeout_seconds: float = DEFAULT_OPENCLAW_TIMEOUT_SECONDS

    def __post_init__(self) -> None:
        if not self.allowed_chat_ids:
            raise ValueError("At least one allowed Telegram chat ID is required.")
        if any(not chat_id for chat_id in self.allowed_chat_ids):
            raise ValueError("Allowed Telegram chat IDs must not be empty.")
        if self.openclaw_timeout_seconds <= 0:
            raise ValueError("OpenClaw timeout must be positive.")
        self.status_client()

    @classmethod
    def from_allowed_chat_ids(
        cls,
        allowed_chat_ids: Iterable[str | int],
        openclaw_base_url: str = DEFAULT_OPENCLAW_BASE_URL,
        openclaw_timeout_seconds: float = DEFAULT_OPENCLAW_TIMEOUT_SECONDS,
    ) -> "TelegramAdapterConfig":
        return cls(
            allowed_chat_ids=parse_allowed_chat_ids(allowed_chat_ids),
            openclaw_base_url=openclaw_base_url,
            openclaw_timeout_seconds=openclaw_timeout_seconds,
        )

    @classmethod
    def from_allowed_chat_ids_text(
        cls,
        allowed_chat_ids_text: str,
        openclaw_base_url: str = DEFAULT_OPENCLAW_BASE_URL,
        openclaw_timeout_seconds: float = DEFAULT_OPENCLAW_TIMEOUT_SECONDS,
    ) -> "TelegramAdapterConfig":
        return cls.from_allowed_chat_ids(
            parse_allowed_chat_ids_text(allowed_chat_ids_text),
            openclaw_base_url=openclaw_base_url,
            openclaw_timeout_seconds=openclaw_timeout_seconds,
        )

    def status_client(self) -> OpenClawStatusClient:
        return OpenClawStatusClient(
            base_url=self.openclaw_base_url,
            timeout_seconds=self.openclaw_timeout_seconds,
        )


def parse_allowed_chat_ids(values: Iterable[str | int]) -> frozenset[str]:
    chat_ids = frozenset(str(value).strip() for value in values)
    if "" in chat_ids:
        raise ValueError("Allowed Telegram chat IDs must not be empty.")
    if any(not _is_valid_chat_id(chat_id) for chat_id in chat_ids):
        raise ValueError("Allowed Telegram chat IDs must be numeric.")
    return chat_ids


def parse_allowed_chat_ids_text(value: str) -> frozenset[str]:
    return parse_allowed_chat_ids(part for part in value.split(",") if part.strip())


def _is_valid_chat_id(value: str) -> bool:
    return value.isdigit() or (value.startswith("-") and value[1:].isdigit())
