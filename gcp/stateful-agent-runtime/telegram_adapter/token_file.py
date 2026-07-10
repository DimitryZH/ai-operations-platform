"""Explicit Telegram token file reader for approved runtime wiring.

This module reads only an operator-provided absolute file path. It does not
read Secret Manager payloads, discover token paths, log token contents, or wire
the token into runtime startup.
"""

from __future__ import annotations

import re
from pathlib import Path, PurePosixPath, PureWindowsPath


_TOKEN_PATTERN = re.compile(r"^[0-9]{6,20}:[A-Za-z0-9_-]{20,}$")


class TelegramTokenFileError(RuntimeError):
    """Safe token file error with reason-only diagnostics."""

    def __init__(self, reason: str) -> None:
        super().__init__(f"Telegram token file error: {reason}")
        self.reason = reason

    def __repr__(self) -> str:
        return f"TelegramTokenFileError(reason={self.reason!r})"


def read_telegram_token_file(path: str) -> str:
    """Read and validate a token from an explicit absolute file path."""

    if not path or not path.strip():
        raise TelegramTokenFileError("missing_path")

    token_path_text = path.strip()
    if not _is_absolute_path(token_path_text):
        raise TelegramTokenFileError("path_not_absolute")

    read_failed = False
    missing_file = False
    try:
        raw_token = Path(token_path_text).read_text(encoding="utf-8")
    except FileNotFoundError:
        missing_file = True
        raw_token = ""
    except OSError:
        read_failed = True
        raw_token = ""

    if missing_file:
        raise TelegramTokenFileError("file_not_found")

    if read_failed:
        raise TelegramTokenFileError("read_error")

    token = raw_token.strip()
    if not token:
        raise TelegramTokenFileError("empty_token")

    if not _TOKEN_PATTERN.match(token):
        raise TelegramTokenFileError("invalid_token_shape")

    return token


def _is_absolute_path(value: str) -> bool:
    return PurePosixPath(value).is_absolute() or PureWindowsPath(value).is_absolute()
