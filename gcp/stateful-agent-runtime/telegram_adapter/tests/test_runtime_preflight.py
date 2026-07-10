import io
import json
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from telegram_adapter.runtime_preflight import (
    ENV_ALLOWED_CHAT_IDS,
    ENV_BOT_TOKEN_FILE,
    ENV_OPENCLAW_BASE_URL,
    RuntimePreflightConfig,
    main,
    run_preflight,
)


TOKEN_CONTENT = "fake-token-content-that-must-not-appear"


def valid_config(
    *,
    allowed_chat_ids_text: str = "12345,-67890",
    bot_token_file: str = "/run/openclaw/secrets/TELEGRAM_BOT_TOKEN",
    openclaw_base_url: str = "http://127.0.0.1:8080",
) -> RuntimePreflightConfig:
    return RuntimePreflightConfig(
        allowed_chat_ids_text=allowed_chat_ids_text,
        bot_token_file=bot_token_file,
        openclaw_base_url=openclaw_base_url,
    )


class RuntimePreflightTests(unittest.TestCase):
    def test_valid_preflight_with_default_openclaw_url(self) -> None:
        result = run_preflight(valid_config())

        self.assertTrue(result.config_valid)
        self.assertTrue(result.allowed_chat_ids_configured)
        self.assertTrue(result.bot_token_file_configured)
        self.assertTrue(result.bot_token_file_absolute)
        self.assertTrue(result.openclaw_base_url_valid)
        self.assertEqual(result.diagnostics[0].reason, "ready")

    def test_valid_preflight_with_laptop_iap_override(self) -> None:
        result = run_preflight(
            valid_config(openclaw_base_url="http://127.0.0.1:18080")
        )

        self.assertTrue(result.config_valid)
        self.assertTrue(result.openclaw_base_url_valid)

    def test_missing_allowed_chat_ids(self) -> None:
        result = run_preflight(valid_config(allowed_chat_ids_text=" "))

        self.assertFalse(result.config_valid)
        self.assertFalse(result.allowed_chat_ids_configured)
        self.assertEqual(result.diagnostics[0].reason, "missing_allowed_chat_ids")

    def test_invalid_allowed_chat_ids(self) -> None:
        result = run_preflight(valid_config(allowed_chat_ids_text="12345,not-a-number"))

        self.assertFalse(result.config_valid)
        self.assertFalse(result.allowed_chat_ids_configured)
        self.assertEqual(result.diagnostics[0].reason, "invalid_allowed_chat_ids")
        self.assertNotIn("not-a-number", repr(result))

    def test_missing_token_file_path(self) -> None:
        result = run_preflight(valid_config(bot_token_file=""))

        self.assertFalse(result.config_valid)
        self.assertFalse(result.bot_token_file_configured)
        self.assertEqual(result.diagnostics[0].reason, "missing_bot_token_file")

    def test_relative_token_file_path_is_invalid(self) -> None:
        result = run_preflight(valid_config(bot_token_file="secrets/token"))

        self.assertFalse(result.config_valid)
        self.assertTrue(result.bot_token_file_configured)
        self.assertFalse(result.bot_token_file_absolute)
        self.assertEqual(result.diagnostics[0].reason, "bot_token_file_not_absolute")
        self.assertNotIn("secrets/token", repr(result))

    def test_windows_absolute_token_file_path_is_valid(self) -> None:
        result = run_preflight(valid_config(bot_token_file="C:\\secrets\\token"))

        self.assertTrue(result.config_valid)
        self.assertTrue(result.bot_token_file_absolute)

    def test_invalid_non_loopback_openclaw_url(self) -> None:
        result = run_preflight(valid_config(openclaw_base_url="https://example.com"))

        self.assertFalse(result.config_valid)
        self.assertFalse(result.openclaw_base_url_valid)
        self.assertEqual(result.diagnostics[0].reason, "invalid_openclaw_base_url")
        self.assertNotIn("example.com", repr(result))

    def test_sanitized_json_output_does_not_include_token_content(self) -> None:
        result = run_preflight(valid_config(bot_token_file=f"/run/{TOKEN_CONTENT}"))

        payload = json.dumps(result.to_sanitized_dict(), sort_keys=True)

        self.assertTrue(result.config_valid)
        self.assertNotIn(TOKEN_CONTENT, payload)
        self.assertNotIn("TELEGRAM_BOT_TOKEN", payload)

    def test_preflight_does_not_open_token_file(self) -> None:
        with patch("builtins.open", side_effect=AssertionError("must not open")):
            result = run_preflight(valid_config())

        self.assertTrue(result.config_valid)

    def test_preflight_does_not_call_telegram_or_openclaw_network(self) -> None:
        with patch(
            "telegram_adapter.status_snapshot.urlopen"
        ) as mocked_urlopen:
            result = run_preflight(valid_config())

        self.assertTrue(result.config_valid)
        mocked_urlopen.assert_not_called()

    def test_cli_reads_environment_and_returns_zero_when_valid(self) -> None:
        env = {
            ENV_ALLOWED_CHAT_IDS: "12345",
            ENV_BOT_TOKEN_FILE: "/run/openclaw/secrets/TELEGRAM_BOT_TOKEN",
            ENV_OPENCLAW_BASE_URL: "http://127.0.0.1:8080",
        }
        output = io.StringIO()

        with patch.dict("os.environ", env, clear=True), redirect_stdout(output):
            exit_code = main([])

        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["config_valid"])
        self.assertTrue(payload["readiness"]["bot_token_file_absolute"])
        self.assertNotIn("TELEGRAM_BOT_TOKEN", output.getvalue())

    def test_cli_returns_nonzero_when_invalid(self) -> None:
        output = io.StringIO()

        with patch.dict("os.environ", {}, clear=True), redirect_stdout(output):
            exit_code = main([])

        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertFalse(payload["config_valid"])
        self.assertEqual(
            payload["diagnostics"][0]["reason"],
            "missing_allowed_chat_ids",
        )

    def test_cli_rejects_arguments_without_running_preflight(self) -> None:
        output = io.StringIO()

        with redirect_stdout(output):
            exit_code = main(["--unexpected"])

        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 2)
        self.assertFalse(payload["config_valid"])
        self.assertEqual(
            payload["diagnostics"][0]["reason"],
            "arguments_not_supported",
        )


if __name__ == "__main__":
    unittest.main()
