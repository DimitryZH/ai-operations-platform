import tempfile
import unittest
from pathlib import Path

from telegram_adapter.token_file import (
    TelegramTokenFileError,
    read_telegram_token_file,
)


FAKE_TOKEN = "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZ_ab"


class TelegramTokenFileTests(unittest.TestCase):
    def test_reads_valid_fake_token_from_absolute_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            token_path = Path(directory) / "telegram-token"
            token_path.write_text(FAKE_TOKEN, encoding="utf-8")

            token = read_telegram_token_file(str(token_path))

        self.assertEqual(token, FAKE_TOKEN)

    def test_strips_surrounding_whitespace_and_crlf(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            token_path = Path(directory) / "telegram-token"
            token_path.write_text(f"  {FAKE_TOKEN}\r\n", encoding="utf-8")

            token = read_telegram_token_file(str(token_path))

        self.assertEqual(token, FAKE_TOKEN)

    def test_missing_path_fails_safely(self) -> None:
        with self.assertRaises(TelegramTokenFileError) as captured:
            read_telegram_token_file("  ")

        self.assertEqual(captured.exception.reason, "missing_path")

    def test_relative_path_fails_safely(self) -> None:
        with self.assertRaises(TelegramTokenFileError) as captured:
            read_telegram_token_file("relative/token-file")

        self.assertEqual(captured.exception.reason, "path_not_absolute")

    def test_missing_file_fails_safely(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing_path = Path(directory) / "missing-token"

            with self.assertRaises(TelegramTokenFileError) as captured:
                read_telegram_token_file(str(missing_path))

        self.assertEqual(captured.exception.reason, "file_not_found")

    def test_empty_file_fails_safely(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            token_path = Path(directory) / "telegram-token"
            token_path.write_text("\r\n", encoding="utf-8")

            with self.assertRaises(TelegramTokenFileError) as captured:
                read_telegram_token_file(str(token_path))

        self.assertEqual(captured.exception.reason, "empty_token")

    def test_invalid_token_shape_fails_without_content_leak(self) -> None:
        invalid_token = "123456789:bad token value should not leak"
        with tempfile.TemporaryDirectory() as directory:
            token_path = Path(directory) / "telegram-token"
            token_path.write_text(invalid_token, encoding="utf-8")

            with self.assertRaises(TelegramTokenFileError) as captured:
                read_telegram_token_file(str(token_path))

        error_text = f"{captured.exception!s} {captured.exception!r}"
        self.assertEqual(captured.exception.reason, "invalid_token_shape")
        self.assertNotIn(invalid_token, error_text)
        self.assertNotIn("bad token value", error_text)


if __name__ == "__main__":
    unittest.main()
