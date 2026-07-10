import unittest

from telegram_adapter.app import TelegramStatusAdapterApp
from telegram_adapter.commands import RuntimeSnapshot
from telegram_adapter.config import TelegramAdapterConfig
from telegram_adapter.message import InboundMessage


def snapshot() -> RuntimeSnapshot:
    return RuntimeSnapshot(
        adapter_status="ready",
        openclaw_health="healthy",
        openclaw_status="private runtime reachable",
    )


class TelegramStatusAdapterAppTests(unittest.TestCase):
    def test_status_message_uses_fake_message_envelope(self) -> None:
        app = TelegramStatusAdapterApp(
            config=TelegramAdapterConfig.from_allowed_chat_ids_text("12345"),
            snapshot_provider=snapshot,
        )

        response = app.handle_inbound(InboundMessage.from_values("12345", "/status"))

        self.assertTrue(response.authorized)
        self.assertEqual(response.chat_id, "12345")
        self.assertEqual(response.command, "/status")
        self.assertIn("Status: available", response.text)
        self.assertIn("private runtime reachable", response.text)

    def test_health_message_uses_status_snapshot_provider(self) -> None:
        app = TelegramStatusAdapterApp(
            config=TelegramAdapterConfig.from_allowed_chat_ids_text("12345"),
            snapshot_provider=snapshot,
        )

        response = app.handle_inbound(InboundMessage.from_values("12345", "/health"))

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "/health")
        self.assertIn("OpenClaw health: healthy", response.text)

    def test_unknown_chat_id_gets_safe_rejection(self) -> None:
        app = TelegramStatusAdapterApp(
            config=TelegramAdapterConfig.from_allowed_chat_ids_text("12345"),
            snapshot_provider=snapshot,
        )

        response = app.handle_inbound(InboundMessage.from_values("99999", "/status"))

        self.assertFalse(response.authorized)
        self.assertEqual(response.text, "Access denied.")
        self.assertNotIn("12345", response.text)
        self.assertNotIn("99999", response.text)

    def test_unsupported_command_gets_limited_help(self) -> None:
        app = TelegramStatusAdapterApp(
            config=TelegramAdapterConfig.from_allowed_chat_ids_text("12345"),
            snapshot_provider=snapshot,
        )

        response = app.handle_inbound(InboundMessage.from_values("12345", "/ask hi"))

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "/ask")
        self.assertIn("Supported commands", response.text)
        self.assertIn("Not available", response.text)
        self.assertIn("Terraform", response.text)
        self.assertIn("shell", response.text)

    def test_free_form_text_gets_limited_help(self) -> None:
        app = TelegramStatusAdapterApp(
            config=TelegramAdapterConfig.from_allowed_chat_ids_text("12345"),
            snapshot_provider=snapshot,
        )

        response = app.handle_inbound(
            InboundMessage.from_values("12345", "run terraform apply")
        )

        self.assertTrue(response.authorized)
        self.assertEqual(response.command, "run")
        self.assertIn("Supported commands", response.text)
        self.assertNotIn("apply complete", response.text.lower())


if __name__ == "__main__":
    unittest.main()
