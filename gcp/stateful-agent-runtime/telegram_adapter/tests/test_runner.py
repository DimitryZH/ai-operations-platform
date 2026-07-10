import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from telegram_adapter.runner import (
    TelegramRunnerConfig,
    TelegramRunnerError,
    build_runner,
    main,
)
from telegram_adapter.telegram_client import (
    FakeTelegramHttpTransport,
)


FAKE_TOKEN = "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZ_ab"


class TelegramRunnerTests(unittest.TestCase):
    def test_preflight_only_does_not_read_token_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing_token_path = Path(directory) / "missing-token"
            output = io.StringIO()

            with redirect_stdout(output):
                exit_code = main(
                    ["--preflight-only"],
                    environ={
                        "TELEGRAM_ALLOWED_CHAT_IDS": "12345",
                        "TELEGRAM_BOT_TOKEN_FILE": str(missing_token_path),
                        "OPENCLAW_BASE_URL": "http://127.0.0.1:8080",
                    },
                )

        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 0)
        self.assertTrue(payload["config_valid"])
        self.assertNotIn(FAKE_TOKEN, output.getvalue())

    def test_build_runner_does_not_read_token_when_preflight_fails(self) -> None:
        calls: list[str] = []

        def token_reader(path: str) -> str:
            calls.append(path)
            return FAKE_TOKEN

        with self.assertRaises(TelegramRunnerError) as captured:
            build_runner(
                TelegramRunnerConfig(
                    allowed_chat_ids_text="",
                    bot_token_file="/run/openclaw/secrets/TELEGRAM_BOT_TOKEN",
                    openclaw_base_url="http://127.0.0.1:8080",
                ),
                token_reader=token_reader,
                transport=FakeTelegramHttpTransport(),
            )

        self.assertEqual(captured.exception.reason, "preflight_failed")
        self.assertEqual(calls, [])

    def test_poll_once_uses_fake_transport_and_in_memory_offset(self) -> None:
        transport = FakeTelegramHttpTransport(
            responses=[
                {
                    "ok": True,
                    "result": [
                        {
                            "update_id": 10,
                            "message": {
                                "message_id": 7,
                                "chat": {"id": 12345},
                                "text": "/help",
                            },
                        }
                    ],
                },
                {"ok": True, "result": {"message_id": 8}},
            ]
        )
        runner = build_runner(
            TelegramRunnerConfig(
                allowed_chat_ids_text="12345",
                bot_token_file="/run/openclaw/secrets/TELEGRAM_BOT_TOKEN",
                openclaw_base_url="http://127.0.0.1:8080",
            ),
            token_reader=lambda path: FAKE_TOKEN,
            transport=transport,
        )

        result = runner.poll_once()

        self.assertEqual(result.updates_received, 1)
        self.assertEqual(result.responses_sent, 1)
        self.assertEqual(result.next_offset, 11)
        self.assertEqual(runner.offset, 11)
        self.assertEqual(transport.requests[0].method, "getUpdates")
        self.assertEqual(transport.requests[1].method, "sendMessage")
        self.assertNotIn(FAKE_TOKEN, repr(transport.requests))

    def test_loop_requires_positive_max_polls(self) -> None:
        runner = build_runner(
            TelegramRunnerConfig(
                allowed_chat_ids_text="12345",
                bot_token_file="/run/openclaw/secrets/TELEGRAM_BOT_TOKEN",
                openclaw_base_url="http://127.0.0.1:8080",
            ),
            token_reader=lambda path: FAKE_TOKEN,
            transport=FakeTelegramHttpTransport(),
        )

        with self.assertRaises(TelegramRunnerError) as captured:
            runner.run_loop(poll_interval_seconds=0, max_polls=0, sleep=lambda _: None)

        self.assertEqual(captured.exception.reason, "invalid_max_polls")


if __name__ == "__main__":
    unittest.main()
