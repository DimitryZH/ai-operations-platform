"""Disabled runtime preflight for Telegram adapter configuration shape.

The preflight reads only non-secret configuration values. It does not open token
files, call Telegram, call OpenClaw, start polling, or wire runtime services.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from pathlib import PurePosixPath, PureWindowsPath
from typing import Mapping, Sequence

from telegram_adapter.config import (
    parse_allowed_chat_ids_text,
)
from telegram_adapter.defaults import DEFAULT_OPENCLAW_BASE_URL
from telegram_adapter.status_snapshot import (
    OpenClawStatusClient,
)


ENV_ALLOWED_CHAT_IDS = "TELEGRAM_ALLOWED_CHAT_IDS"
ENV_BOT_TOKEN_FILE = "TELEGRAM_BOT_TOKEN_FILE"
ENV_OPENCLAW_BASE_URL = "OPENCLAW_BASE_URL"


@dataclass(frozen=True)
class RuntimePreflightConfig:
    """Non-secret runtime preflight input values."""

    allowed_chat_ids_text: str | None
    bot_token_file: str | None
    openclaw_base_url: str = DEFAULT_OPENCLAW_BASE_URL

    @classmethod
    def from_env(
        cls,
        environ: Mapping[str, str] | None = None,
    ) -> "RuntimePreflightConfig":
        source = os.environ if environ is None else environ
        return cls(
            allowed_chat_ids_text=source.get(ENV_ALLOWED_CHAT_IDS),
            bot_token_file=source.get(ENV_BOT_TOKEN_FILE),
            openclaw_base_url=source.get(
                ENV_OPENCLAW_BASE_URL,
                DEFAULT_OPENCLAW_BASE_URL,
            ),
        )


@dataclass(frozen=True)
class RuntimePreflightDiagnostic:
    """Safe preflight diagnostic with event names and reasons only."""

    event: str
    reason: str


@dataclass(frozen=True)
class RuntimePreflightResult:
    """Sanitized runtime preflight result."""

    config_valid: bool
    allowed_chat_ids_configured: bool
    bot_token_file_configured: bool
    bot_token_file_absolute: bool
    openclaw_base_url_valid: bool
    diagnostics: tuple[RuntimePreflightDiagnostic, ...]

    def to_sanitized_dict(self) -> dict[str, object]:
        return {
            "config_valid": self.config_valid,
            "readiness": {
                "allowed_chat_ids_configured": self.allowed_chat_ids_configured,
                "bot_token_file_configured": self.bot_token_file_configured,
                "bot_token_file_absolute": self.bot_token_file_absolute,
                "openclaw_base_url_valid": self.openclaw_base_url_valid,
            },
            "diagnostics": [
                {"event": item.event, "reason": item.reason}
                for item in self.diagnostics
            ],
        }


def run_preflight(config: RuntimePreflightConfig) -> RuntimePreflightResult:
    diagnostics: list[RuntimePreflightDiagnostic] = []

    allowed_chat_ids_configured = _has_value(config.allowed_chat_ids_text)
    if not allowed_chat_ids_configured:
        diagnostics.append(
            RuntimePreflightDiagnostic(
                event="telegram_runtime_preflight_invalid_config",
                reason="missing_allowed_chat_ids",
            )
        )
    else:
        try:
            parse_allowed_chat_ids_text(config.allowed_chat_ids_text or "")
        except ValueError:
            allowed_chat_ids_configured = False
            diagnostics.append(
                RuntimePreflightDiagnostic(
                    event="telegram_runtime_preflight_invalid_config",
                    reason="invalid_allowed_chat_ids",
                )
            )

    bot_token_file_configured = _has_value(config.bot_token_file)
    bot_token_file_absolute = False
    if not bot_token_file_configured:
        diagnostics.append(
            RuntimePreflightDiagnostic(
                event="telegram_runtime_preflight_invalid_config",
                reason="missing_bot_token_file",
            )
        )
    else:
        bot_token_file_absolute = _is_absolute_path(config.bot_token_file or "")
        if not bot_token_file_absolute:
            diagnostics.append(
                RuntimePreflightDiagnostic(
                    event="telegram_runtime_preflight_invalid_config",
                    reason="bot_token_file_not_absolute",
                )
            )

    openclaw_base_url_valid = True
    try:
        OpenClawStatusClient(base_url=config.openclaw_base_url)
    except ValueError:
        openclaw_base_url_valid = False
        diagnostics.append(
            RuntimePreflightDiagnostic(
                event="telegram_runtime_preflight_invalid_config",
                reason="invalid_openclaw_base_url",
            )
        )

    config_valid = (
        allowed_chat_ids_configured
        and bot_token_file_configured
        and bot_token_file_absolute
        and openclaw_base_url_valid
    )
    if config_valid:
        diagnostics.append(
            RuntimePreflightDiagnostic(
                event="telegram_runtime_preflight_valid",
                reason="ready",
            )
        )

    return RuntimePreflightResult(
        config_valid=config_valid,
        allowed_chat_ids_configured=allowed_chat_ids_configured,
        bot_token_file_configured=bot_token_file_configured,
        bot_token_file_absolute=bot_token_file_absolute,
        openclaw_base_url_valid=openclaw_base_url_valid,
        diagnostics=tuple(diagnostics),
    )


def main(argv: Sequence[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if argv:
        print(
            json.dumps(
                {
                    "config_valid": False,
                    "diagnostics": [
                        {
                            "event": "telegram_runtime_preflight_invalid_cli",
                            "reason": "arguments_not_supported",
                        }
                    ],
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 2

    result = run_preflight(RuntimePreflightConfig.from_env())
    print(json.dumps(result.to_sanitized_dict(), indent=2, sort_keys=True))
    return 0 if result.config_valid else 1


def _has_value(value: str | None) -> bool:
    return bool(value and value.strip())


def _is_absolute_path(value: str) -> bool:
    return PurePosixPath(value).is_absolute() or PureWindowsPath(value).is_absolute()


if __name__ == "__main__":
    sys.exit(main())
