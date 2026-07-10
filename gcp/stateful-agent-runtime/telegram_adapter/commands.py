"""Fixed status-only command handling for the Telegram operator adapter."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Iterable

from telegram_adapter.defaults import SUPPORTED_COMMANDS


@dataclass(frozen=True)
class OperatorContext:
    """Minimal caller context used for allowlist checks."""

    chat_id: str
    allowed_chat_ids: frozenset[str]

    @classmethod
    def from_allowed_ids(
        cls, chat_id: str | int, allowed_chat_ids: Iterable[str | int]
    ) -> "OperatorContext":
        return cls(
            chat_id=str(chat_id),
            allowed_chat_ids=frozenset(str(item) for item in allowed_chat_ids),
        )


@dataclass(frozen=True)
class RuntimeSnapshot:
    """Non-secret runtime state surfaced through status-only commands."""

    adapter_status: str = "ready"
    openclaw_health: str = "unknown"
    openclaw_status: str = "not queried"


@dataclass(frozen=True)
class CommandResponse:
    """Telegram-safe response payload."""

    command: str | None
    authorized: bool
    text: str


SnapshotProvider = Callable[[], RuntimeSnapshot]


def default_snapshot_provider() -> RuntimeSnapshot:
    """Return a safe placeholder until live OpenClaw probing is approved."""

    return RuntimeSnapshot()


def normalize_command(message_text: str) -> str:
    """Extract a fixed Telegram command without preserving raw message text."""

    text = (message_text or "").strip()
    if not text:
        return "/help"
    command = text.split(maxsplit=1)[0].lower()
    if "@" in command:
        command = command.split("@", maxsplit=1)[0]
    return command


def handle_message(
    message_text: str,
    context: OperatorContext,
    snapshot_provider: SnapshotProvider = default_snapshot_provider,
) -> CommandResponse:
    """Route one Telegram message through fixed status-only handlers.

    This function performs no network calls, shell execution, config mutation, or
    tool invocation. Runtime state is supplied by a narrow injected snapshot
    provider so tests can validate command behavior without secrets.
    """

    command = normalize_command(message_text)

    if context.chat_id not in context.allowed_chat_ids:
        return CommandResponse(
            command=command,
            authorized=False,
            text="Access denied.",
        )

    if command == "/status":
        return _status_response(snapshot_provider())
    if command == "/health":
        return _health_response(snapshot_provider())
    if command == "/whoami":
        return _whoami_response()
    if command == "/help":
        return _help_response(command="/help")

    return _help_response(command=command)


def _status_response(snapshot: RuntimeSnapshot) -> CommandResponse:
    return CommandResponse(
        command="/status",
        authorized=True,
        text=(
            "Status: available\n"
            f"Adapter: {snapshot.adapter_status}\n"
            f"OpenClaw: {snapshot.openclaw_status}\n"
            "Scope: status-only"
        ),
    )


def _health_response(snapshot: RuntimeSnapshot) -> CommandResponse:
    return CommandResponse(
        command="/health",
        authorized=True,
        text=(
            "Health: checked\n"
            f"OpenClaw health: {snapshot.openclaw_health}\n"
            "Scope: status-only"
        ),
    )


def _whoami_response() -> CommandResponse:
    return CommandResponse(
        command="/whoami",
        authorized=True,
        text=(
            "Identity: approved Telegram chat\n"
            "Role: mobile status operator\n"
            "Permissions: /status, /health, /whoami, /help"
        ),
    )


def _help_response(command: str) -> CommandResponse:
    return CommandResponse(
        command=command,
        authorized=True,
        text=(
            "Supported commands: /status, /health, /whoami, /help\n"
            "Not available: /ask, GitHub commands, PR/write, Terraform, shell, "
            "browser automation, MCP, DevBox"
        ),
    )
