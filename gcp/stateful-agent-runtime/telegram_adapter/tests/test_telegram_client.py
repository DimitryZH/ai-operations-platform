import reprlib
import unittest

from telegram_adapter.telegram_client import (
    FakeTelegramHttpTransport,
    TelegramApiError,
    TelegramBotApiClient,
)


FAKE_TOKEN = "fake-token-for-tests-only"


def client(
    transport: FakeTelegramHttpTransport,
    default_timeout_seconds: int = 30,
) -> TelegramBotApiClient:
    return TelegramBotApiClient(
        token=FAKE_TOKEN,
        transport=transport,
        default_timeout_seconds=default_timeout_seconds,
    )


class TelegramBotApiClientTests(unittest.TestCase):
    def test_get_updates_builds_get_updates_request(self) -> None:
        transport = FakeTelegramHttpTransport(
            responses=[{"ok": True, "result": [{"update_id": 1}]}]
        )

        result = client(transport).get_updates()

        self.assertEqual(result, [{"update_id": 1}])
        self.assertEqual(len(transport.requests), 1)
        self.assertEqual(transport.requests[0].method, "getUpdates")
        self.assertEqual(transport.requests[0].payload, {"timeout": 30})
        self.assertNotIn(FAKE_TOKEN, repr(transport.requests[0]))

    def test_get_updates_includes_offset_and_timeout(self) -> None:
        transport = FakeTelegramHttpTransport()

        client(transport).get_updates(offset=42, timeout_seconds=5)

        self.assertEqual(
            transport.requests[0].payload,
            {"timeout": 5, "offset": 42},
        )

    def test_send_message_builds_send_message_request(self) -> None:
        transport = FakeTelegramHttpTransport(
            responses=[{"ok": True, "result": {"message_id": 7}}]
        )

        result = client(transport).send_message(chat_id="12345", text="hello")

        self.assertEqual(result, {"message_id": 7})
        self.assertEqual(transport.requests[0].method, "sendMessage")
        self.assertEqual(
            transport.requests[0].payload,
            {"chat_id": "12345", "text": "hello"},
        )

    def test_send_message_includes_reply_to_message_id(self) -> None:
        transport = FakeTelegramHttpTransport()

        client(transport).send_message(
            chat_id="12345",
            text="hello",
            reply_to_message_id=10,
        )

        self.assertEqual(
            transport.requests[0].payload,
            {"chat_id": "12345", "text": "hello", "reply_to_message_id": 10},
        )

    def test_repr_redacts_token(self) -> None:
        transport = FakeTelegramHttpTransport()

        client_repr = repr(client(transport))

        self.assertIn("token=<redacted>", client_repr)
        self.assertNotIn(FAKE_TOKEN, client_repr)

    def test_api_not_ok_raises_safe_error(self) -> None:
        transport = FakeTelegramHttpTransport(
            responses=[
                {
                    "ok": False,
                    "error_code": 400,
                    "description": "bad request with fake-token-for-tests-only hello 99999",
                }
            ]
        )

        with self.assertRaises(TelegramApiError) as captured:
            client(transport).send_message(chat_id="99999", text="hello")

        error_text = f"{captured.exception!s} {captured.exception!r}"
        self.assertIn("ok=false", error_text)
        self.assertEqual(captured.exception.method, "sendMessage")
        self.assertEqual(captured.exception.reason, "api_not_ok")
        self.assertEqual(captured.exception.error_code, 400)
        self.assertNotIn(FAKE_TOKEN, error_text)
        self.assertNotIn("hello", error_text)
        self.assertNotIn("99999", error_text)

    def test_http_exception_raises_safe_error(self) -> None:
        transport = FakeTelegramHttpTransport(
            exception=RuntimeError(
                "network failed with fake-token-for-tests-only secret text 99999"
            )
        )

        with self.assertRaises(TelegramApiError) as captured:
            client(transport).get_updates()

        error_text = f"{captured.exception!s} {captured.exception!r}"
        self.assertIn("transport failed", error_text)
        self.assertEqual(captured.exception.method, "getUpdates")
        self.assertEqual(captured.exception.reason, "transport_error")
        self.assertIsNone(captured.exception.__context__)
        self.assertNotIn(FAKE_TOKEN, error_text)
        self.assertNotIn("secret text", error_text)
        self.assertNotIn("99999", error_text)

    def test_invalid_response_raises_safe_error(self) -> None:
        transport = FakeTelegramHttpTransport(responses=["not-a-json-object"])

        with self.assertRaises(TelegramApiError) as captured:
            client(transport).get_updates()

        self.assertEqual(captured.exception.reason, "invalid_response")
        self.assertNotIn(FAKE_TOKEN, repr(captured.exception))

    def test_fake_transport_repr_does_not_include_token(self) -> None:
        transport = FakeTelegramHttpTransport()

        client(transport).send_message(chat_id="12345", text="secret text")

        self.assertNotIn(FAKE_TOKEN, reprlib.repr(transport))


if __name__ == "__main__":
    unittest.main()
