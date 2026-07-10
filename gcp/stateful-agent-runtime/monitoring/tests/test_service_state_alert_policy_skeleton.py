import re
import unittest
from pathlib import Path


STATEFUL_VM_ROOT = Path(__file__).resolve().parents[2]
TERRAFORM_DIR = STATEFUL_VM_ROOT / "terraform"

ALERT_POLICY_TF = TERRAFORM_DIR / "service_state_alert_policy.tf"
EXPORTER_TF = TERRAFORM_DIR / "service_state_exporter.tf"
TFVARS_EXAMPLE = TERRAFORM_DIR / "terraform.tfvars.example"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def variable_block(terraform_text: str, variable_name: str) -> str:
    match = re.search(
        rf'variable\s+"{re.escape(variable_name)}"\s+\{{(?P<body>.*?)\n\}}',
        terraform_text,
        flags=re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"Missing Terraform variable {variable_name}")
    return match.group("body")


class ServiceStateAlertPolicySkeletonTests(unittest.TestCase):
    def test_alert_policy_defaults_are_disabled(self) -> None:
        terraform_text = read(ALERT_POLICY_TF)

        self.assertRegex(
            variable_block(terraform_text, "service_state_alert_policy_create"),
            r"default\s+=\s+false",
        )
        self.assertRegex(
            variable_block(terraform_text, "service_state_alert_policy_enabled"),
            r"default\s+=\s+false",
        )
        self.assertIn(
            "count = var.service_state_alert_policy_create ? 1 : 0",
            terraform_text,
        )
        self.assertIn("enabled               = var.service_state_alert_policy_enabled", terraform_text)
        self.assertIn("notification_channels = []", terraform_text)

    def test_enabled_policy_requires_create_check(self) -> None:
        terraform_text = read(ALERT_POLICY_TF)

        self.assertIn(
            'check "service_state_alert_policy_enabled_requires_create"',
            terraform_text,
        )
        self.assertIn(
            "!var.service_state_alert_policy_enabled || var.service_state_alert_policy_create",
            terraform_text,
        )

    def test_metric_prefix_and_service_label_bounds_are_fail_closed(self) -> None:
        alert_text = read(ALERT_POLICY_TF)
        exporter_text = read(EXPORTER_TF)

        self.assertRegex(
            variable_block(exporter_text, "service_state_exporter_metric_prefix"),
            r'default\s+=\s+"custom\.googleapis\.com/openclaw/service_state"',
        )
        self.assertIn(
            'startswith(var.service_state_exporter_metric_prefix, "custom.googleapis.com/")',
            alert_text,
        )
        self.assertIn('metric.label.service = one_of(', alert_text)
        self.assertIn('"openclaw.service"', alert_text)
        self.assertIn('check "service_state_alert_policy_has_approved_services"', alert_text)

    def test_alert_policy_targets_only_bounded_service_state_metrics(self) -> None:
        terraform_text = read(ALERT_POLICY_TF)

        self.assertIn("google_monitoring_alert_policy", terraform_text)
        self.assertIn("${var.service_state_exporter_metric_prefix}/healthy", terraform_text)
        self.assertIn("${var.service_state_exporter_metric_prefix}/available", terraform_text)
        self.assertIn("${var.service_state_exporter_metric_prefix}/active", terraform_text)
        self.assertIn("${var.service_state_exporter_metric_prefix}/running", terraform_text)
        self.assertIn("COMPARISON_LT", terraform_text)
        self.assertIn("threshold_value = var.service_state_alert_threshold", terraform_text)
        self.assertNotIn("journal", terraform_text.lower())
        self.assertNotIn("logging.googleapis.com", terraform_text)

    def test_alert_policy_skeleton_does_not_introduce_unapproved_resources(self) -> None:
        terraform_text = read(ALERT_POLICY_TF)
        forbidden_patterns = {
            "notification channel resource": r'(?m)^\s*resource\s+"google_monitoring_notification_channel"',
            "logs-based metric resource": r'(?m)^\s*resource\s+"google_logging_metric"',
            "project iam resource": r'(?m)^\s*resource\s+"google_project_iam',
            "service account iam resource": r'(?m)^\s*resource\s+"google_service_account_iam',
            "secret data source": r'(?m)^\s*data\s+"google_secret_manager_secret_version"',
        }

        for label, pattern in forbidden_patterns.items():
            with self.subTest(label=label):
                self.assertIsNone(re.search(pattern, terraform_text))

    def test_tfvars_example_keeps_alert_policy_disabled_and_contains_no_sensitive_values(self) -> None:
        tfvars_text = read(TFVARS_EXAMPLE)
        forbidden_patterns = {
            "notification channel id": r"notificationChannels/[0-9]",
            "operator token value": r"OPERATOR_SECRET_TOKEN=.*[0-9].*:.*",
            "webhook url": r"https?://[^\s]*webhook",
            "callback url": r"callbackUrl",
            "raw token assignment": r"token\s*=",
            "chat id value": r"chat_id\s*=",
        }

        self.assertRegex(tfvars_text, r"service_state_alert_policy_create\s+=\s+false")
        self.assertRegex(tfvars_text, r"service_state_alert_policy_enabled\s+=\s+false")

        for label, pattern in forbidden_patterns.items():
            with self.subTest(label=label):
                self.assertIsNone(re.search(pattern, tfvars_text))


if __name__ == "__main__":
    unittest.main()
