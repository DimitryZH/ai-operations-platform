"""Prepared runtime runner for the Telegram status-only adapter.

This module is explicit runtime wiring only. It is not imported by any existing
startup path and does not run unless an operator invokes this module directly.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from telegram_adapter.app import TelegramStatusAdapterApp
from telegram_adapter.config import TelegramAdapterConfig
from telegram_adapter.defaults import DEFAULT_OPENCLAW_BASE_URL
from telegram_adapter.polling import (
    PollOnceResult,
    TelegramPollOnceCoordinator,
)
from telegram_adapter.runtime_preflight import (
    ENV_ALLOWED_CHAT_IDS,
    ENV_BOT_TOKEN_FILE,
    ENV_OPENCLAW_BASE_URL,
    RuntimePreflightConfig,
    run_preflight,
)
from telegram_adapter.telegram_client import (
    TelegramBotApiClient,
    TelegramHttpTransport,
    UrllibTelegramHttpTransport,
)
from telegram_adapter.token_file import (
    TelegramTokenFileError,
    read_telegram_token_file,
)
from telegram_adapter.transport import (
    FakeTelegramDispatcher,
)


TokenReader = Callable[[str], str]


class TelegramRunnerError(RuntimeError):
    """Safe runner error with reason-only diagnostics."""

    def __init__(self, reason: str) -> None:
        super().__init__(f"Telegram adapter runner error: {reason}")
        self.reason = reason

    def __repr__(self) -> str:
        return f"TelegramRunnerError(reason={self.reason!r})"


@dataclass(frozen=True)
class TelegramRunnerConfig:
    """Non-secret runtime runner configuration."""

    allowed_chat_ids_text: str | None
    bot_token_file: str | None
    openclaw_base_url: str = DEFAULT_OPENCLAW_BASE_URL

    @classmethod
    def from_env(
        cls,
        environ: Mapping[str, str] | None = None,
    ) -> "TelegramRunnerConfig":
        source = os.environ if environ is None else environ
        return cls(
            allowed_chat_ids_text=source.get(ENV_ALLOWED_CHAT_IDS),
            bot_token_file=source.get(ENV_BOT_TOKEN_FILE),
            openclaw_base_url=source.get(
                ENV_OPENCLAW_BASE_URL,
                DEFAULT_OPENCLAW_BASE_URL,
            ),
        )

    def preflight_config(self) -> RuntimePreflightConfig:
        return RuntimePreflightConfig(
            allowed_chat_ids_text=self.allowed_chat_ids_text,
            bot_token_file=self.bot_token_file,
            openclaw_base_url=self.openclaw_base_url,
        )


class TelegramAdapterRunner:
    """Maintain in-memory update offset for explicit runtime polling."""

    def __init__(self, coordinator: TelegramPollOnceCoordinator) -> None:
        self._coordinator = coordinator
        self._offset: int | None = None

    @property
    def offset(self) -> int | None:
        return self._offset

    def poll_once(self) -> PollOnceResult:
        result = self._coordinator.poll_once(offset=self._offset)
        self._offset = result.next_offset
        return result

    def run_loop(
        self,
        *,
        poll_interval_seconds: float,
        max_polls: int | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ) -> int:
        if poll_interval_seconds < 0:
            raise TelegramRunnerError("invalid_poll_interval")
        if max_polls is not None and max_polls <= 0:
            raise TelegramRunnerError("invalid_max_polls")

        polls_completed = 0
        while max_polls is None or polls_completed < max_polls:
            self.poll_once()
            polls_completed += 1
            if max_polls is None or polls_completed < max_polls:
                sleep(poll_interval_seconds)
        return polls_completed


def build_runner(
    config: TelegramRunnerConfig,
    *,
    token_reader: TokenReader = read_telegram_token_file,
    transport: TelegramHttpTransport | None = None,
) -> TelegramAdapterRunner:
    """Validate config, read the explicit token file, and build runtime wiring."""

    preflight = run_preflight(config.preflight_config())
    if not preflight.config_valid:
        raise TelegramRunnerError("preflight_failed")

    if config.bot_token_file is None:
        raise TelegramRunnerError("missing_bot_token_file")

    try:
        token = token_reader(config.bot_token_file)
    except TelegramTokenFileError as exc:
        raise TelegramRunnerError(f"token_file_{exc.reason}") from None

    adapter_config = TelegramAdapterConfig.from_allowed_chat_ids_text(
        config.allowed_chat_ids_text or "",
        openclaw_base_url=config.openclaw_base_url,
    )
    app = TelegramStatusAdapterApp(adapter_config)
    dispatcher = FakeTelegramDispatcher(app)
    client = TelegramBotApiClient(
        token=token,
        transport=transport or UrllibTelegramHttpTransport(),
    )
    coordinator = TelegramPollOnceCoordinator(client=client, dispatcher=dispatcher)
    return TelegramAdapterRunner(coordinator)


def main(
    argv: Sequence[str] | None = None,
    *,
    environ: Mapping[str, str] | None = None,
) -> int:
    parser = argparse.ArgumentParser(
        description="Prepared Telegram status-only adapter runtime runner."
    )
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--preflight-only", action="store_true")
    modes.add_argument("--poll-once", action="store_true")
    modes.add_argument("--loop", action="store_true")
    parser.add_argument("--poll-interval-seconds", type=float, default=5.0)
    parser.add_argument("--max-polls", type=int, default=None)

    args = parser.parse_args(argv)
    config = TelegramRunnerConfig.from_env(environ)
    preflight = run_preflight(config.preflight_config())

    if args.preflight_only:
        print(json.dumps(preflight.to_sanitized_dict(), indent=2, sort_keys=True))
        return 0 if preflight.config_valid else 1

    if not preflight.config_valid:
        print(
            json.dumps(
                {
                    "runner_started": False,
                    "preflight": preflight.to_sanitized_dict(),
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    try:
        runner = build_runner(config)
        if args.poll_once:
            result = runner.poll_once()
            output: dict[str, Any] = {
                "runner_started": True,
                "mode": "poll_once",
                "poll": _poll_result_to_sanitized_dict(result),
            }
        else:
            polls_completed = runner.run_loop(
                poll_interval_seconds=args.poll_interval_seconds,
                max_polls=args.max_polls,
            )
            output = {
                "runner_started": True,
                "mode": "loop",
                "polls_completed": polls_completed,
                "next_offset_known": runner.offset is not None,
            }
    except TelegramRunnerError as exc:
        output = {
            "runner_started": False,
            "diagnostics": [
                {
                    "event": "telegram_runner_start_failed",
                    "reason": exc.reason,
                }
            ],
        }
        print(json.dumps(output, indent=2, sort_keys=True))
        return 1

    print(json.dumps(output, indent=2, sort_keys=True))
    return 0


def _poll_result_to_sanitized_dict(result: PollOnceResult) -> dict[str, object]:
    return {
        "updates_received": result.updates_received,
        "updates_processed": result.updates_processed,
        "responses_sent": result.responses_sent,
        "malformed_updates": result.malformed_updates,
        "next_offset_known": result.next_offset is not None,
        "diagnostics": [
            {
                "event": item.event,
                "reason": item.reason,
            }
            for item in result.diagnostics
        ],
    }


if __name__ == "__main__":
    sys.exit(main())
