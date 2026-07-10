"""Poll-once coordinator for Telegram adapter tests and runtime.

This module models one polling cycle. The runtime loop is owned by
telegram_adapter.runner.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Protocol

from telegram_adapter.telegram_client import TelegramApiError
from telegram_adapter.transport import (
    DispatchResult,
    FakeTelegramDispatcher,
)


class TelegramPollClient(Protocol):
    """Minimal client surface needed for one poll cycle."""

    def get_updates(self, *, offset: int | None = None) -> Any:
        """Return decoded Telegram update objects from an injected client."""

    def send_message(
        self,
        *,
        chat_id: str | int,
        text: str,
        reply_to_message_id: str | int | None = None,
    ) -> Any:
        """Send one message through an injected client."""


@dataclass(frozen=True)
class PollDiagnostic:
    """Safe poll diagnostic with event names and reasons only."""

    event: str
    reason: str | None = None


@dataclass(frozen=True)
class PollOnceResult:
    """Safe result for one poll cycle."""

    updates_received: int
    updates_processed: int
    responses_sent: int
    malformed_updates: int
    next_offset: int | None
    diagnostics: tuple[PollDiagnostic, ...]


class TelegramPollOnceCoordinator:
    """Coordinate one Telegram poll pass through injected fake/test dependencies."""

    def __init__(
        self,
        *,
        client: TelegramPollClient,
        dispatcher: FakeTelegramDispatcher,
    ) -> None:
        self._client = client
        self._dispatcher = dispatcher

    def poll_once(self, offset: int | None = None) -> PollOnceResult:
        diagnostics: list[PollDiagnostic] = []
        try:
            updates = self._client.get_updates(offset=offset)
        except TelegramApiError as exc:
            return PollOnceResult(
                updates_received=0,
                updates_processed=0,
                responses_sent=0,
                malformed_updates=0,
                next_offset=offset,
                diagnostics=(
                    PollDiagnostic(
                        event="telegram_poll_get_updates_error",
                        reason=exc.reason,
                    ),
                ),
            )

        if not isinstance(updates, list):
            return PollOnceResult(
                updates_received=0,
                updates_processed=0,
                responses_sent=0,
                malformed_updates=0,
                next_offset=offset,
                diagnostics=(
                    PollDiagnostic(
                        event="telegram_poll_invalid_updates",
                        reason="non_list_result",
                    ),
                ),
            )

        updates_processed = 0
        responses_sent = 0
        malformed_updates = 0
        max_update_id = offset - 1 if offset is not None else None

        for update in updates:
            update_id = _integer_update_id(update)
            if update_id is not None:
                if max_update_id is None or update_id > max_update_id:
                    max_update_id = update_id

            if not isinstance(update, Mapping):
                malformed_updates += 1
                diagnostics.append(
                    PollDiagnostic(
                        event="telegram_poll_malformed_update",
                        reason="invalid_update_shape",
                    )
                )
                continue

            dispatch = self._dispatcher.dispatch(update)
            updates_processed += 1
            if dispatch.diagnostic.malformed_reason is not None:
                malformed_updates += 1
                diagnostics.append(
                    PollDiagnostic(
                        event=dispatch.diagnostic.event,
                        reason=dispatch.diagnostic.malformed_reason,
                    )
                )

            if dispatch.outbound is None:
                continue

            if self._send_outbound(dispatch, diagnostics):
                responses_sent += 1

        return PollOnceResult(
            updates_received=len(updates),
            updates_processed=updates_processed,
            responses_sent=responses_sent,
            malformed_updates=malformed_updates,
            next_offset=(None if max_update_id is None else max_update_id + 1),
            diagnostics=tuple(diagnostics),
        )

    def _send_outbound(
        self,
        dispatch: DispatchResult,
        diagnostics: list[PollDiagnostic],
    ) -> bool:
        outbound = dispatch.outbound
        if outbound is None:
            return False

        try:
            self._client.send_message(
                chat_id=outbound.chat_id,
                text=outbound.text,
                reply_to_message_id=outbound.reply_to_message_id,
            )
        except TelegramApiError as exc:
            diagnostics.append(
                PollDiagnostic(
                    event="telegram_poll_send_message_error",
                    reason=exc.reason,
                )
            )
            return False
        return True


def _integer_update_id(update: Any) -> int | None:
    if not isinstance(update, Mapping):
        return None
    update_id = update.get("update_id")
    return update_id if isinstance(update_id, int) else None
