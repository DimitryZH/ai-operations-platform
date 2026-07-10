import dataclasses
import unittest

from telegram_adapter.diagnostics import (
    safe_diagnostic_event,
)
from telegram_adapter.message import InboundMessage


class AdapterDiagnosticsTests(unittest.TestCase):
    def test_safe_event_strips_bot_suffix_without_raw_message_text(self) -> None:
        event = safe_diagnostic_event(
            InboundMessage.from_values("12345", "/status@SomeBot include token"),
            frozenset({"12345"}),
        )
        payload = dataclasses.asdict(event)

        self.assertEqual(payload["event"], "telegram_adapter_message")
        self.assertEqual(payload["command"], "/status")
        self.assertTrue(payload["authorized"])
        self.assertTrue(payload["supported"])
        self.assertNotIn("include token", str(payload))
        self.assertNotIn("12345", str(payload))

    def test_safe_event_does_not_expose_unknown_chat_id(self) -> None:
        event = safe_diagnostic_event(
            InboundMessage.from_values("99999", "/ask@SomeBot hi"),
            frozenset({"12345"}),
        )
        payload = dataclasses.asdict(event)

        self.assertEqual(payload["command"], "/ask")
        self.assertFalse(payload["authorized"])
        self.assertFalse(payload["supported"])
        self.assertNotIn("99999", str(payload))
        self.assertNotIn("12345", str(payload))
        self.assertNotIn("hi", str(payload))


if __name__ == "__main__":
    unittest.main()
