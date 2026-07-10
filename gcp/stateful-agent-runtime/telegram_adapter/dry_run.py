"""Local dry-run CLI for fake Telegram-like adapter updates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Sequence

from telegram_adapter.app import TelegramStatusAdapterApp
from telegram_adapter.commands import RuntimeSnapshot
from telegram_adapter.config import TelegramAdapterConfig
from telegram_adapter.transport import (
    FakeTelegramDispatcher,
    TransportDiagnosticEvent,
)


def main(argv: Sequence[str] | None = None) -> int:
    result = run_dry_run(argv)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def run_dry_run(argv: Sequence[str] | None = None) -> dict[str, Any]:
    parser = _build_parser()
    args = parser.parse_args(argv)

    loaded = _load_update(args)
    if loaded.error is not None:
        return _sanitized_result(
            would_send=False,
            outbound_text=None,
            diagnostic=TransportDiagnosticEvent(
                event="telegram_adapter_invalid_input",
                command=None,
                authorized=False,
                supported=False,
                malformed_reason=loaded.error,
            ),
        )

    try:
        config = TelegramAdapterConfig.from_allowed_chat_ids_text(
            allowed_chat_ids_text=args.allowed_chat_ids,
            openclaw_base_url=args.openclaw_base_url,
        )
    except ValueError:
        return _sanitized_result(
            would_send=False,
            outbound_text=None,
            diagnostic=TransportDiagnosticEvent(
                event="telegram_adapter_invalid_config",
                command=None,
                authorized=False,
                supported=False,
                malformed_reason="invalid_config",
            ),
        )

    dispatcher = FakeTelegramDispatcher(
        TelegramStatusAdapterApp(
            config=config,
            snapshot_provider=_fake_snapshot,
        )
    )
    dispatch = dispatcher.dispatch(loaded.update)
    return _sanitized_result(
        would_send=dispatch.outbound is not None,
        outbound_text=dispatch.outbound.text if dispatch.outbound else None,
        diagnostic=dispatch.diagnostic,
    )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Dry-run fake Telegram-like updates without Telegram access.",
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--update-json", help="One fake Telegram-like update as JSON.")
    source.add_argument("--update-file", help="Path to one fake update JSON file.")
    parser.add_argument(
        "--allowed-chat-ids",
        required=True,
        help="Comma-separated non-secret Telegram chat ID allowlist.",
    )
    parser.add_argument(
        "--openclaw-base-url",
        default="http://127.0.0.1:8080",
        help=(
            "Loopback OpenClaw base URL to validate. The dry-run uses a fake "
            "snapshot by default and does not call this URL."
        ),
    )
    return parser


class _LoadedUpdate:
    def __init__(self, update: dict[str, Any], error: str | None = None) -> None:
        self.update = update
        self.error = error


def _load_update(args: argparse.Namespace) -> _LoadedUpdate:
    if args.update_file:
        try:
            raw = Path(args.update_file).read_text(encoding="utf-8")
        except OSError:
            return _LoadedUpdate(update={}, error="update_file_read_error")
    else:
        raw = args.update_json

    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return _LoadedUpdate(update={}, error="invalid_json")

    if not isinstance(parsed, dict):
        return _LoadedUpdate(update={}, error="invalid_update_shape")

    return _LoadedUpdate(update=parsed)


def _fake_snapshot() -> RuntimeSnapshot:
    return RuntimeSnapshot(
        adapter_status="dry-run",
        openclaw_health="not queried",
        openclaw_status="fake snapshot",
    )


def _sanitized_result(
    would_send: bool,
    outbound_text: str | None,
    diagnostic: TransportDiagnosticEvent,
) -> dict[str, Any]:
    return {
        "would_send": would_send,
        "outbound_response_text": outbound_text,
        "diagnostic": {
            "event": diagnostic.event,
            "command": diagnostic.command,
            "authorized": diagnostic.authorized,
            "supported": diagnostic.supported,
            "malformed_reason": diagnostic.malformed_reason,
        },
    }


if __name__ == "__main__":
    sys.exit(main())
