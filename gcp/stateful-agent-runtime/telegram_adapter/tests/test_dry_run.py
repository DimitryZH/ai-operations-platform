import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from telegram_adapter.dry_run import main, run_dry_run


def update(chat_id: str | int, text: object) -> str:
    return json.dumps(
        {
            "update_id": 1,
            "message": {
                "message_id": 10,
                "chat": {"id": chat_id},
                "text": text,
            },
        }
    )


class TelegramDryRunTests(unittest.TestCase):
    def test_valid_status_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                update("12345", "/status"),
            ]
        )

        self.assertTrue(result["would_send"])
        self.assertIn("Status: available", result["outbound_response_text"])
        self.assertEqual(result["diagnostic"]["command"], "/status")
        self.assertTrue(result["diagnostic"]["authorized"])

    def test_valid_health_dry_run_uses_fake_snapshot(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                update("12345", "/health"),
            ]
        )

        self.assertTrue(result["would_send"])
        self.assertIn("OpenClaw health: not queried", result["outbound_response_text"])
        self.assertEqual(result["diagnostic"]["command"], "/health")

    def test_valid_whoami_dry_run_does_not_echo_chat_id(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                update("12345", "/whoami"),
            ]
        )

        self.assertTrue(result["would_send"])
        self.assertIn("approved Telegram chat", result["outbound_response_text"])
        self.assertNotIn("12345", result["outbound_response_text"])

    def test_unsupported_ask_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                update("12345", "/ask@SomeBot secret text"),
            ]
        )

        self.assertTrue(result["would_send"])
        self.assertIn("Supported commands", result["outbound_response_text"])
        self.assertEqual(result["diagnostic"]["command"], "/ask")
        self.assertFalse(result["diagnostic"]["supported"])
        self.assertNotIn("secret text", json.dumps(result))

    def test_unknown_chat_id_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                update("99999", "/status"),
            ]
        )

        self.assertTrue(result["would_send"])
        self.assertEqual(result["outbound_response_text"], "Access denied.")
        self.assertFalse(result["diagnostic"]["authorized"])
        self.assertNotIn("99999", json.dumps(result))

    def test_invalid_json_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                "{not-json}",
            ]
        )

        self.assertFalse(result["would_send"])
        self.assertEqual(result["diagnostic"]["event"], "telegram_adapter_invalid_input")
        self.assertEqual(result["diagnostic"]["malformed_reason"], "invalid_json")
        self.assertNotIn("not-json", json.dumps(result))

    def test_missing_message_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                '{"update_id":1}',
            ]
        )

        self.assertFalse(result["would_send"])
        self.assertEqual(result["diagnostic"]["malformed_reason"], "missing_message")

    def test_missing_chat_id_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                '{"message":{"message_id":10,"chat":{},"text":"/status secret"}}',
            ]
        )

        self.assertFalse(result["would_send"])
        self.assertEqual(result["diagnostic"]["command"], "/status")
        self.assertEqual(result["diagnostic"]["malformed_reason"], "missing_chat_id")
        self.assertNotIn("secret", json.dumps(result))

    def test_missing_text_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                '{"message":{"chat":{"id":12345}}}',
            ]
        )

        self.assertFalse(result["would_send"])
        self.assertEqual(result["diagnostic"]["command"], "/help")
        self.assertEqual(result["diagnostic"]["malformed_reason"], "missing_text")

    def test_non_string_text_dry_run(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--update-json",
                update("12345", {"text": "/status"}),
            ]
        )

        self.assertFalse(result["would_send"])
        self.assertEqual(result["diagnostic"]["malformed_reason"], "missing_text")

    def test_update_file_dry_run(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            update_file = Path(temp_dir) / "update.json"
            update_file.write_text(update("12345", "/help"), encoding="utf-8")

            result = run_dry_run(
                [
                    "--allowed-chat-ids",
                    "12345",
                    "--update-file",
                    str(update_file),
                ]
            )

        self.assertTrue(result["would_send"])
        self.assertEqual(result["diagnostic"]["command"], "/help")

    def test_laptop_iap_override_is_validated_without_live_call(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--openclaw-base-url",
                "http://127.0.0.1:18080",
                "--update-json",
                update("12345", "/health"),
            ]
        )

        self.assertTrue(result["would_send"])
        self.assertIn("not queried", result["outbound_response_text"])

    def test_invalid_openclaw_url_returns_sanitized_config_error(self) -> None:
        result = run_dry_run(
            [
                "--allowed-chat-ids",
                "12345",
                "--openclaw-base-url",
                "https://example.com",
                "--update-json",
                update("12345", "/status"),
            ]
        )

        self.assertFalse(result["would_send"])
        self.assertEqual(result["diagnostic"]["event"], "telegram_adapter_invalid_config")
        self.assertNotIn("example.com", json.dumps(result))

    def test_main_prints_sanitized_json(self) -> None:
        output = io.StringIO()
        with redirect_stdout(output):
            exit_code = main(
                [
                    "--allowed-chat-ids",
                    "12345",
                    "--update-json",
                    update("12345", "/help"),
                ]
            )

        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["would_send"])
        self.assertEqual(payload["diagnostic"]["command"], "/help")


if __name__ == "__main__":
    unittest.main()
