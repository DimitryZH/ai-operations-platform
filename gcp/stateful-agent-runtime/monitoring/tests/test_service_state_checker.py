import io
import json
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from monitoring import service_state_checker as checker


def systemctl_output(
    service: str,
    *,
    load: str = "loaded",
    active: str = "active",
    sub: str = "running",
    result: str = "success",
    exec_status: str = "0",
    unit: str = "enabled",
) -> str:
    return "\n".join(
        [
            f"Id={service}",
            f"LoadState={load}",
            f"ActiveState={active}",
            f"SubState={sub}",
            f"Result={result}",
            f"ExecMainStatus={exec_status}",
            f"UnitFileState={unit}",
            "ActiveEnterTimestamp=Sat 2026-07-04 19:22:56 UTC",
            "InactiveEnterTimestamp=",
        ]
    )


class Completed:
    def __init__(self, stdout: str, returncode: int = 0) -> None:
        self.stdout = stdout
        self.returncode = returncode


def metric_map(payload: dict) -> dict[tuple[str, str], int]:
    return {
        (metric["labels"]["service"], metric["name"]): metric["value"]
        for metric in payload["metrics"]
    }


class ServiceStateCheckerTests(unittest.TestCase):
    def test_active_running_service_is_healthy(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output("openclaw.service")
            ),
        )

        self.assertTrue(state.is_healthy())
        self.assertTrue(state.is_healthy(strict=True))

    def test_inactive_failed_service_is_unhealthy(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output(
                    "openclaw.service",
                    active="failed",
                    sub="failed",
                    result="exit-code",
                    exec_status="1",
                )
            ),
        )

        self.assertFalse(state.is_healthy())
        self.assertEqual(state.reason(), "inactive")

    def test_missing_service_is_unhealthy(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output("openclaw.service", load="not-found", active="inactive", sub="dead")
            ),
        )

        self.assertFalse(state.is_healthy())
        self.assertEqual(state.reason(), "service_unavailable")

    def test_unhealthy_requested_service_returns_nonzero(self) -> None:
        outputs = {
            "openclaw.service": systemctl_output(
                "openclaw.service",
                active="inactive",
                sub="dead",
            ),
        }

        def fake_run(command, **kwargs):
            return Completed(outputs[command[2]])

        with patch.object(checker.subprocess, "run", side_effect=fake_run):
            with redirect_stdout(io.StringIO()):
                exit_code = checker.main(
                    [
                        "--service",
                        "openclaw.service",
                        "--format",
                        "json",
                    ]
                )

        self.assertEqual(exit_code, 1)

    def test_json_output_contains_only_bounded_fields(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output("openclaw.service")
                + "\nEnvironment=SECRET=do-not-print"
                + "\nExecStart=/bin/command --token secret"
                + "\nStatusText=raw log line"
            ),
        )

        payload = json.loads(checker.render_json([state]))
        service_payload = payload["services"][0]

        self.assertEqual(
            sorted(service_payload["properties"].keys()),
            sorted(checker.ALLOWED_PROPERTIES),
        )
        serialized = json.dumps(payload)
        self.assertNotIn("SECRET", serialized)
        self.assertNotIn("ExecStart", serialized)
        self.assertNotIn("raw log line", serialized)
        self.assertNotIn("token", serialized)

    def test_text_output_does_not_emit_raw_log_like_payload(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output("openclaw.service")
                + "\nLogLine=operator message secret text"
            ),
        )

        output = checker.render_text([state])

        self.assertIn("openclaw.service healthy", output)
        self.assertNotIn("operator message", output)
        self.assertNotIn("secret text", output)

    def test_systemctl_not_found_is_unhealthy(self) -> None:
        with patch.object(checker.subprocess, "run", side_effect=FileNotFoundError):
            state = checker.run_systemctl_show("openclaw.service")

        self.assertFalse(state.is_healthy())
        self.assertEqual(state.reason(), "systemctl_not_found")

    def test_metrics_json_healthy_service_emits_expected_values(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(systemctl_output("openclaw.service")),
        )

        payload = json.loads(checker.render_metrics_json([state]))
        metrics = metric_map(payload)

        self.assertTrue(payload["ok"])
        self.assertFalse(payload["strict"])
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_healthy")],
            1,
        )
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_available")],
            1,
        )
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_active")],
            1,
        )
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_running")],
            1,
        )

    def test_metrics_json_inactive_service_emits_unhealthy_state(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output("openclaw.service", active="inactive", sub="dead")
            ),
        )

        payload = json.loads(checker.render_metrics_json([state]))
        metrics = metric_map(payload)

        self.assertFalse(payload["ok"])
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_healthy")],
            0,
        )
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_available")],
            1,
        )
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_active")],
            0,
        )
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_running")],
            0,
        )

    def test_metrics_json_missing_service_emits_unavailable_state(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output(
                    "openclaw.service",
                    load="not-found",
                    active="inactive",
                    sub="dead",
                )
            ),
        )

        payload = json.loads(checker.render_metrics_json([state]))
        metrics = metric_map(payload)

        self.assertFalse(payload["ok"])
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_healthy")],
            0,
        )
        self.assertEqual(
            metrics[("openclaw.service", "openclaw_service_state_available")],
            0,
        )

    def test_metrics_json_has_bounded_metrics_and_labels(self) -> None:
        states = [
            checker.ServiceState(
                service="openclaw.service",
                properties=checker.parse_systemctl_show(
                    systemctl_output("openclaw.service")
                ),
            ),
        ]

        payload = json.loads(checker.render_metrics_json(states))

        self.assertEqual(
            len(payload["metrics"]),
            len(states) * len(checker.METRIC_NAMES),
        )
        self.assertEqual(
            sorted({metric["labels"]["service"] for metric in payload["metrics"]}),
            ["openclaw.service"],
        )
        for metric in payload["metrics"]:
            self.assertIn(metric["name"], checker.METRIC_NAMES)
            self.assertEqual(sorted(metric["labels"].keys()), ["service"])
            self.assertIn(metric["value"], {0, 1})

    def test_metrics_json_excludes_timestamps_raw_output_and_sensitive_strings(self) -> None:
        state = checker.ServiceState(
            service="openclaw.service",
            properties=checker.parse_systemctl_show(
                systemctl_output("openclaw.service")
                + "\nEnvironment=OPERATOR_SECRET_TOKEN=redacted"
                + "\nExecStart=/bin/command --token secret"
                + "\nStatusText=operator payload text"
                + "\nLogLine=raw log payload"
                + "\nSecretValue=secret"
            ),
        )

        serialized = checker.render_metrics_json([state])

        self.assertNotIn("Timestamp", serialized)
        self.assertNotIn("OPERATOR_SECRET_TOKEN", serialized)
        self.assertNotIn("ExecStart", serialized)
        self.assertNotIn("command", serialized)
        self.assertNotIn("operator payload text", serialized)
        self.assertNotIn("raw log payload", serialized)
        self.assertNotIn("SecretValue", serialized)
        self.assertNotIn("secret", serialized)

    def test_metrics_json_cli_uses_mocked_systemctl_without_external_dependencies(self) -> None:
        def fake_run(command, **kwargs):
            return Completed(systemctl_output(command[2]))

        with patch.object(checker.subprocess, "run", side_effect=fake_run) as run_mock:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                exit_code = checker.main(
                    ["--service", "openclaw.service", "--format", "metrics-json"]
                )

        payload = json.loads(buffer.getvalue())
        command = run_mock.call_args.args[0]

        self.assertEqual(exit_code, 0)
        self.assertIn("metrics", payload)
        self.assertEqual(
            command[:4],
            ["systemctl", "show", "openclaw.service", "--no-pager"],
        )
        self.assertEqual(
            sorted(arg.replace("--property=", "") for arg in command[4:]),
            sorted(checker.ALLOWED_PROPERTIES),
        )


if __name__ == "__main__":
    unittest.main()
