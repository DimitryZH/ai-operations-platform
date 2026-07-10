import dataclasses
import unittest

from telegram_adapter.app import TelegramStatusAdapterApp
from telegram_adapter.commands import RuntimeSnapshot
from telegram_adapter.config import TelegramAdapterConfig
from telegram_adapter.polling import TelegramPollOnceCoordinator
from telegram_adapter.telegram_client import TelegramApiError
from telegram_adapter.transport import FakeTelegramDispatcher


FAKE_TOKEN = "fake-token-for-tests-only"


class FakePollClient:
    def __init__(
        self,
        updates: object,
        *,
        get_error: TelegramApiError | None = None,
        send_error: TelegramApiError | None = None,
    ) -> None:
        self.updates = updates
        self.get_error = get_error
        self.send_error = send_error
        self.get_offsets: list[int | None] = []
        self.sent_messages: list[dict[str, object]] = []

    def get_updates(self, *, offset: int | None = None) -> object:
        self.get_offsets.append(offset)
        if self.get_error is not None:
            raise self.get_error
        return self.updates

    def send_message(
        self,
        *,
        chat_id: str | int,
        text: str,
        reply_to_message_id: str | int | None = None,
    ) -> object:
        if self.send_error is not None:
            raise self.send_error
        self.sent_messages.append(
            {
                "chat_id": chat_id,
                "text": text,
                "reply_to_message_id": reply_to_message_id,
            }
        )
        return {"message_id": 100}


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


def coordinator(client: FakePollClient) -> TelegramPollOnceCoordinator:
    return TelegramPollOnceCoordinator(client=client, dispatcher=dispatcher())


def update(
    chat_id: str | int,
    text: object,
    update_id: object = 42,
    message_id: int = 7,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "message": {
            "message_id": message_id,
            "chat": {"id": chat_id},
            "text": text,
        }
    }
    if update_id is not None:
        payload["update_id"] = update_id
    return payload


class TelegramPollOnceCoordinatorTests(unittest.TestCase):
    def test_poll_once_with_no_updates(self) -> None:
        client = FakePollClient([])

        result = coordinator(client).poll_once(offset=10)

        self.assertEqual(client.get_offsets, [10])
        self.assertEqual(result.updates_received, 0)
        self.assertEqual(result.updates_processed, 0)
        self.assertEqual(result.responses_sent, 0)
        self.assertEqual(result.malformed_updates, 0)
        self.assertEqual(result.next_offset, 10)
        self.assertEqual(result.diagnostics, ())

    def test_poll_once_with_status_response(self) -> None:
        client = FakePollClient([update("12345", "/status", update_id=42)])

        result = coordinator(client).poll_once()

        self.assertEqual(result.updates_received, 1)
        self.assertEqual(result.updates_processed, 1)
        self.assertEqual(result.responses_sent, 1)
        self.assertEqual(result.next_offset, 43)
        self.assertIn("Status: available", client.sent_messages[0]["text"])
        self.assertEqual(client.sent_messages[0]["reply_to_message_id"], "7")

    def test_poll_once_with_help_response(self) -> None:
        client = FakePollClient([update("12345", "/help", update_id=43)])

        result = coordinator(client).poll_once(offset=40)

        self.assertEqual(result.responses_sent, 1)
        self.assertEqual(result.next_offset, 44)
        self.assertIn("Supported commands", client.sent_messages[0]["text"])

    def test_unknown_chat_id_sends_no_sensitive_data(self) -> None:
        client = FakePollClient([update("99999", "/health secret text", update_id=44)])

        result = coordinator(client).poll_once()

        self.assertEqual(result.responses_sent, 1)
        self.assertEqual(client.sent_messages[0]["text"], "Access denied.")
        result_text = repr(result)
        self.assertNotIn("99999", result_text)
        self.assertNotIn("secret text", result_text)

    def test_malformed_update_counted_safely(self) -> None:
        client = FakePollClient(
            [{"update_id": 45, "message": {"chat": {}, "text": "/status secret"}}]
        )

        result = coordinator(client).poll_once()

        self.assertEqual(result.updates_received, 1)
        self.assertEqual(result.updates_processed, 1)
        self.assertEqual(result.responses_sent, 0)
        self.assertEqual(result.malformed_updates, 1)
        self.assertEqual(result.next_offset, 46)
        self.assertEqual(
            dataclasses.asdict(result.diagnostics[0]),
            {
                "event": "telegram_adapter_malformed_update",
                "reason": "missing_chat_id",
            },
        )
        self.assertNotIn("secret", repr(result))

    def test_next_offset_uses_max_integer_update_id(self) -> None:
        client = FakePollClient(
            [
                update("12345", "/status", update_id=50),
                update("12345", "/health", update_id=49),
            ]
        )

        result = coordinator(client).poll_once(offset=40)

        self.assertEqual(result.next_offset, 51)

    def test_missing_and_non_integer_update_id_are_ignored_for_next_offset(self) -> None:
        client = FakePollClient(
            [
                update("12345", "/status", update_id=None),
                update("12345", "/health", update_id="not-an-int"),
            ]
        )

        result = coordinator(client).poll_once()

        self.assertEqual(result.updates_received, 2)
        self.assertEqual(result.responses_sent, 2)
        self.assertIsNone(result.next_offset)

    def test_non_list_get_updates_result_handled_safely(self) -> None:
        client = FakePollClient({"unexpected": "shape"})

        result = coordinator(client).poll_once(offset=20)

        self.assertEqual(result.updates_received, 0)
        self.assertEqual(result.updates_processed, 0)
        self.assertEqual(result.responses_sent, 0)
        self.assertEqual(result.next_offset, 20)
        self.assertEqual(result.diagnostics[0].event, "telegram_poll_invalid_updates")
        self.assertEqual(result.diagnostics[0].reason, "non_list_result")

    def test_get_updates_telegram_api_error_handled_safely(self) -> None:
        client = FakePollClient(
            [],
            get_error=TelegramApiError(
                "Telegram API transport failed with fake-token-for-tests-only secret",
                method="getUpdates",
                reason="transport_error",
            ),
        )

        result = coordinator(client).poll_once(offset=30)

        self.assertEqual(result.updates_received, 0)
        self.assertEqual(result.responses_sent, 0)
        self.assertEqual(result.next_offset, 30)
        self.assertEqual(result.diagnostics[0].event, "telegram_poll_get_updates_error")
        self.assertEqual(result.diagnostics[0].reason, "transport_error")
        self.assertNotIn(FAKE_TOKEN, repr(result))
        self.assertNotIn("secret", repr(result))

    def test_send_message_telegram_api_error_handled_safely(self) -> None:
        client = FakePollClient(
            [update("12345", "/status secret text", update_id=60)],
            send_error=TelegramApiError(
                "Telegram API returned ok=false with fake-token-for-tests-only 12345",
                method="sendMessage",
                reason="api_not_ok",
                error_code=400,
            ),
        )

        result = coordinator(client).poll_once()

        self.assertEqual(result.responses_sent, 0)
        self.assertEqual(result.next_offset, 61)
        self.assertEqual(result.diagnostics[0].event, "telegram_poll_send_message_error")
        self.assertEqual(result.diagnostics[0].reason, "api_not_ok")
        self.assertNotIn(FAKE_TOKEN, repr(result))
        self.assertNotIn("secret text", repr(result))
        self.assertNotIn("12345", repr(result))

    def test_non_mapping_update_is_counted_as_malformed(self) -> None:
        client = FakePollClient(["not-a-dict"])

        result = coordinator(client).poll_once()

        self.assertEqual(result.updates_received, 1)
        self.assertEqual(result.updates_processed, 0)
        self.assertEqual(result.responses_sent, 0)
        self.assertEqual(result.malformed_updates, 1)
        self.assertIsNone(result.next_offset)
        self.assertEqual(result.diagnostics[0].reason, "invalid_update_shape")


if __name__ == "__main__":
    unittest.main()
