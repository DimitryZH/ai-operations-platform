import json
import unittest

from telegram_adapter.telegram_client import (
    TelegramApiError,
    UrllibTelegramHttpTransport,
)


FAKE_TOKEN = "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZ_ab"


class FakePost:
    def __init__(self, response: bytes = b'{"ok":true,"result":{"message_id":7}}'):
        self.response = response
        self.calls: list[tuple[str, bytes, dict[str, str], float]] = []

    def __call__(
        self,
        url: str,
        body: bytes,
        headers: dict[str, str],
        timeout_seconds: float,
    ) -> bytes:
        self.calls.append((url, body, dict(headers), timeout_seconds))
        return self.response


class TelegramHttpTransportTests(unittest.TestCase):
    def test_sends_json_payload_through_injected_post_function(self) -> None:
        fake_post = FakePost()
        transport = UrllibTelegramHttpTransport(
            post_json=fake_post,
            timeout_seconds=9.5,
        )

        response = transport.post_json(
            token=FAKE_TOKEN,
            method="sendMessage",
            payload={"chat_id": "12345", "text": "hello"},
        )

        self.assertEqual(response, {"ok": True, "result": {"message_id": 7}})
        self.assertEqual(len(fake_post.calls), 1)
        url, body, headers, timeout_seconds = fake_post.calls[0]
        self.assertEqual(
            url,
            f"https://api.telegram.org/bot{FAKE_TOKEN}/sendMessage",
        )
        self.assertEqual(
            json.loads(body.decode("utf-8")),
            {"chat_id": "12345", "text": "hello"},
        )
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(headers["Accept"], "application/json")
        self.assertEqual(timeout_seconds, 9.5)

    def test_repr_does_not_include_token_or_url_path(self) -> None:
        transport = UrllibTelegramHttpTransport()

        text = repr(transport)

        self.assertIn("base_url=<redacted>", text)
        self.assertNotIn("api.telegram.org", text)
        self.assertNotIn(FAKE_TOKEN, text)

    def test_invalid_json_maps_to_safe_error(self) -> None:
        transport = UrllibTelegramHttpTransport(post_json=FakePost(b"not-json"))

        with self.assertRaises(TelegramApiError) as captured:
            transport.post_json(
                token=FAKE_TOKEN,
                method="sendMessage",
                payload={"chat_id": "99999", "text": "secret text"},
            )

        error_text = f"{captured.exception!s} {captured.exception!r}"
        self.assertEqual(captured.exception.reason, "invalid_json")
        self.assertEqual(captured.exception.method, "sendMessage")
        self.assertIsNone(captured.exception.__context__)
        self.assertNotIn(FAKE_TOKEN, error_text)
        self.assertNotIn("99999", error_text)
        self.assertNotIn("secret text", error_text)

    def test_non_object_json_maps_to_safe_error(self) -> None:
        transport = UrllibTelegramHttpTransport(post_json=FakePost(b"[]"))

        with self.assertRaises(TelegramApiError) as captured:
            transport.post_json(
                token=FAKE_TOKEN,
                method="getUpdates",
                payload={"timeout": 1},
            )

        self.assertEqual(captured.exception.reason, "invalid_response")
        self.assertNotIn(FAKE_TOKEN, repr(captured.exception))

    def test_http_error_maps_to_safe_error_without_context(self) -> None:
        leaked_message = f"network failed {FAKE_TOKEN} secret text 99999"

        def failing_post(
            url: str,
            body: bytes,
            headers: dict[str, str],
            timeout_seconds: float,
        ) -> bytes:
            raise RuntimeError(leaked_message)

        transport = UrllibTelegramHttpTransport(post_json=failing_post)

        with self.assertRaises(TelegramApiError) as captured:
            transport.post_json(
                token=FAKE_TOKEN,
                method="sendMessage",
                payload={"chat_id": "99999", "text": "secret text"},
            )

        error_text = f"{captured.exception!s} {captured.exception!r}"
        self.assertEqual(captured.exception.reason, "http_error")
        self.assertEqual(captured.exception.method, "sendMessage")
        self.assertIsNone(captured.exception.__context__)
        self.assertNotIn(FAKE_TOKEN, error_text)
        self.assertNotIn("99999", error_text)
        self.assertNotIn("secret text", error_text)
        self.assertNotIn(leaked_message, error_text)


if __name__ == "__main__":
    unittest.main()
