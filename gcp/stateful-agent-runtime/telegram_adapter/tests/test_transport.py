import dataclasses
import unittest

from telegram_adapter.app import TelegramStatusAdapterApp
from telegram_adapter.commands import RuntimeSnapshot
from telegram_adapter.config import TelegramAdapterConfig
from telegram_adapter.transport import FakeTelegramDispatcher


def snapshot() -> RuntimeSnapshot:
    return RuntimeSnapshot(
        adapter_status="ready",
        openclaw_health="healthy",
        openclaw_status="private runtime reachable",
    )


def dispatcher() -> FakeTelegramDispatcher:
    return FakeTelegramDispatcher(
        TelegramStatusAdapterApp(
            config=TelegramAdapterConfig.from_allowed_chat_ids_text("12345"),
            snapshot_provider=snapshot,
        )
    )


def update(chat_id: str | int, text: object, message_id: int = 7) -> dict[str, object]:
    return {
        "update_id": 42,
        "message": {
            "message_id": message_id,
            "chat": {"id": chat_id},
            "text": text,
        },
    }


class FakeTelegramDispatcherTests(unittest.TestCase):
    def test_dispatches_status_update_to_adapter_app(self) -> None:
        result = dispatcher().dispatch(update("12345", "/status@SomeBot"))

        self.assertIsNotNone(result.outbound)
        self.assertEqual(result.outbound.chat_id, "12345")
        self.assertEqual(result.outbound.reply_to_message_id, "7")
        self.assertIn("Status: available", result.outbound.text)
        self.assertEqual(result.diagnostic.command, "/status")
        self.assertTrue(result.diagnostic.authorized)
        self.assertTrue(result.diagnostic.supported)
        self.assertEqual(result.update_id, "42")

    def test_dispatches_unknown_chat_to_safe_rejection(self) -> None:
        result = dispatcher().dispatch(update("99999", "/health"))

        self.assertIsNotNone(result.outbound)
        self.assertEqual(result.outbound.text, "Access denied.")
        self.assertFalse(result.diagnostic.authorized)
        self.assertTrue(result.diagnostic.supported)
        self.assertNotIn("99999", str(dataclasses.asdict(result.diagnostic)))

    def test_dispatches_unsupported_command_to_limited_help(self) -> None:
        result = dispatcher().dispatch(update("12345", "/ask@SomeBot hi"))

        self.assertIsNotNone(result.outbound)
        self.assertIn("Supported commands", result.outbound.text)
        self.assertIn("Not available", result.outbound.text)
        self.assertEqual(result.diagnostic.command, "/ask")
        self.assertFalse(result.diagnostic.supported)
        self.assertNotIn("hi", str(dataclasses.asdict(result.diagnostic)))

    def test_dispatches_free_form_text_to_limited_help(self) -> None:
        result = dispatcher().dispatch(update("12345", "run terraform apply"))

        self.assertIsNotNone(result.outbound)
        self.assertIn("Supported commands", result.outbound.text)
        self.assertEqual(result.diagnostic.command, "run")
        self.assertFalse(result.diagnostic.supported)
        self.assertNotIn("terraform apply", str(dataclasses.asdict(result.diagnostic)))

    def test_missing_message_is_malformed_without_outbound(self) -> None:
        result = dispatcher().dispatch({"update_id": 42})

        self.assertIsNone(result.outbound)
        self.assertEqual(result.diagnostic.event, "telegram_adapter_malformed_update")
        self.assertEqual(result.diagnostic.malformed_reason, "missing_message")
        self.assertFalse(result.diagnostic.authorized)

    def test_missing_chat_id_is_malformed_without_raw_text_leak(self) -> None:
        result = dispatcher().dispatch(
            {"message": {"message_id": 7, "chat": {}, "text": "/status secret text"}}
        )

        self.assertIsNone(result.outbound)
        self.assertEqual(result.diagnostic.command, "/status")
        self.assertEqual(result.diagnostic.malformed_reason, "missing_chat_id")
        self.assertNotIn("secret text", str(dataclasses.asdict(result.diagnostic)))

    def test_missing_text_is_malformed_without_outbound(self) -> None:
        result = dispatcher().dispatch({"message": {"chat": {"id": "12345"}}})

        self.assertIsNone(result.outbound)
        self.assertEqual(result.diagnostic.command, "/help")
        self.assertEqual(result.diagnostic.malformed_reason, "missing_text")

    def test_non_string_text_is_malformed_without_outbound(self) -> None:
        result = dispatcher().dispatch(update("12345", {"text": "/status"}))

        self.assertIsNone(result.outbound)
        self.assertEqual(result.diagnostic.command, "/help")
        self.assertEqual(result.diagnostic.malformed_reason, "missing_text")


if __name__ == "__main__":
    unittest.main()
