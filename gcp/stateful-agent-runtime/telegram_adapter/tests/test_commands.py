import unittest

from telegram_adapter.commands import (
    OperatorContext,
    RuntimeSnapshot,
    handle_message,
    normalize_command,
)


def snapshot() -> RuntimeSnapshot:
    return RuntimeSnapshot(
        adapter_status="ready",
        openclaw_health="healthy",
        openclaw_status="private runtime reachable",
    )


class TelegramStatusOnlyCommandTests(unittest.TestCase):
    def test_normalize_command_ignores_arguments(self) -> None:
        self.assertEqual(normalize_command(" /STATUS please "), "/status")

    def test_normalize_command_strips_telegram_bot_suffix(self) -> None:
        self.assertEqual(normalize_command("/status@SomeBot"), "/status")
        self.assertEqual(normalize_command("/HEALTH@SomeBot"), "/health")
        self.assertEqual(normalize_command("/ask@SomeBot hi"), "/ask")

    def test_approved_status_returns_non_secret_status(self) -> None:
        context = OperatorContext.from_allowed_ids("12345", ["12345"])

        response = handle_message("/status", context, snapshot)

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "/status")
        self.assertIn("Status: available", response.text)
        self.assertIn("OpenClaw: private runtime reachable", response.text)
        self.assertNotIn("token", response.text.lower())
        self.assertNotIn("secret", response.text.lower())

    def test_approved_health_returns_non_secret_health(self) -> None:
        context = OperatorContext.from_allowed_ids("12345", ["12345"])

        response = handle_message("/health", context, snapshot)

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "/health")
        self.assertIn("OpenClaw health: healthy", response.text)
        self.assertIn("Scope: status-only", response.text)

    def test_whoami_does_not_echo_chat_id(self) -> None:
        context = OperatorContext.from_allowed_ids("12345", ["12345"])

        response = handle_message("/whoami", context, snapshot)

        self.assertTrue(response.authorized)
        self.assertNotIn("12345", response.text)
        self.assertIn("approved Telegram chat", response.text)

    def test_unknown_user_is_rejected_without_details(self) -> None:
        context = OperatorContext.from_allowed_ids("99999", ["12345"])

        response = handle_message("/status", context, snapshot)

        self.assertFalse(response.authorized)
        self.assertEqual(response.text, "Access denied.")
        self.assertNotIn("12345", response.text)
        self.assertNotIn("99999", response.text)

    def test_unknown_command_returns_limited_help(self) -> None:
        context = OperatorContext.from_allowed_ids("12345", ["12345"])

        response = handle_message("/ask summarize incident", context, snapshot)

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "/ask")
        self.assertIn("Supported commands", response.text)
        self.assertIn("Not available", response.text)
        self.assertIn("Terraform", response.text)
        self.assertIn("shell", response.text)

    def test_unknown_command_with_bot_suffix_returns_limited_help(self) -> None:
        context = OperatorContext.from_allowed_ids("12345", ["12345"])

        response = handle_message("/ask@SomeBot summarize incident", context, snapshot)

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "/ask")
        self.assertIn("Supported commands", response.text)
        self.assertIn("Not available", response.text)

    def test_empty_message_returns_help(self) -> None:
        context = OperatorContext.from_allowed_ids("12345", ["12345"])

        response = handle_message("   ", context, snapshot)

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "/help")
        self.assertIn("/status", response.text)


if __name__ == "__main__":
    unittest.main()
