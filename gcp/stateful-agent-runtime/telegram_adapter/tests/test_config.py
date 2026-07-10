import unittest

from telegram_adapter.config import (
    TelegramAdapterConfig,
    parse_allowed_chat_ids,
    parse_allowed_chat_ids_text,
)


class TelegramAdapterConfigTests(unittest.TestCase):
    def test_config_default_openclaw_url_is_vm_local_runtime_port(self) -> None:
        config = TelegramAdapterConfig.from_allowed_chat_ids_text("12345")

        self.assertEqual(config.openclaw_base_url, "http://127.0.0.1:8080")

    def test_parse_allowed_chat_ids_text_trims_values(self) -> None:
        self.assertEqual(
            parse_allowed_chat_ids_text(" 12345,67890 "),
            frozenset({"12345", "67890"}),
        )

    def test_parse_allowed_chat_ids_rejects_empty_value(self) -> None:
        with self.assertRaises(ValueError):
            parse_allowed_chat_ids(["12345", " "])

    def test_parse_allowed_chat_ids_rejects_non_numeric_value(self) -> None:
        with self.assertRaises(ValueError):
            parse_allowed_chat_ids(["12345", "not-a-chat"])

    def test_parse_allowed_chat_ids_allows_negative_group_id(self) -> None:
        self.assertEqual(parse_allowed_chat_ids(["-10012345"]), frozenset({"-10012345"}))

    def test_config_rejects_empty_allowlist(self) -> None:
        with self.assertRaises(ValueError):
            TelegramAdapterConfig.from_allowed_chat_ids_text("")

    def test_config_accepts_loopback_openclaw_url(self) -> None:
        config = TelegramAdapterConfig.from_allowed_chat_ids_text(
            "12345",
            openclaw_base_url="http://127.0.0.1:8080",
        )

        self.assertEqual(config.allowed_chat_ids, frozenset({"12345"}))
        self.assertEqual(config.openclaw_base_url, "http://127.0.0.1:8080")

    def test_config_accepts_laptop_iap_test_override(self) -> None:
        config = TelegramAdapterConfig.from_allowed_chat_ids_text(
            "12345",
            openclaw_base_url="http://127.0.0.1:18080",
        )

        self.assertEqual(config.openclaw_base_url, "http://127.0.0.1:18080")

    def test_config_rejects_non_loopback_openclaw_url(self) -> None:
        with self.assertRaises(ValueError):
            TelegramAdapterConfig.from_allowed_chat_ids_text(
                "12345",
                openclaw_base_url="https://example.com",
            )

    def test_config_rejects_non_positive_timeout(self) -> None:
        with self.assertRaises(ValueError):
            TelegramAdapterConfig.from_allowed_chat_ids_text(
                "12345",
                openclaw_timeout_seconds=0,
            )


if __name__ == "__main__":
    unittest.main()
