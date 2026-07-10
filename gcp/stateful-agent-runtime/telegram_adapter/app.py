"""Non-enabled application layer for the Telegram status-only adapter."""

from __future__ import annotations

from telegram_adapter.commands import (
    OperatorContext,
    SnapshotProvider,
    handle_message,
)
from telegram_adapter.config import TelegramAdapterConfig
from telegram_adapter.message import (
    InboundMessage,
    OutboundMessage,
)


class TelegramStatusAdapterApp:
    """Wire config, command handling, and status snapshots without polling."""

    def __init__(
        self,
        config: TelegramAdapterConfig,
        snapshot_provider: SnapshotProvider | None = None,
    ) -> None:
        self._config = config
        self._snapshot_provider = snapshot_provider or config.status_client().snapshot

    def handle_inbound(self, message: InboundMessage) -> OutboundMessage:
        context = OperatorContext(
            chat_id=message.chat_id,
            allowed_chat_ids=self._config.allowed_chat_ids,
        )
        response = handle_message(
            message_text=message.text,
            context=context,
            snapshot_provider=self._snapshot_provider,
        )
        return OutboundMessage(
            chat_id=message.chat_id,
            text=response.text,
            authorized=response.authorized,
            command=response.command,
        )
