import io
import json
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

from monitoring import service_state_checker as checker
from monitoring import service_state_monitor_runner as runner


PROJECT_ID = "your-gcp-project-id"


def service_state(
    service: str,
    *,
    load: str = "loaded",
    active: str = "active",
    sub: str = "running",
    result: str = "success",
    exec_status: str = "0",
    unit: str = "enabled",
) -> checker.ServiceState:
    return checker.ServiceState(
        service=service,
        properties={
            "Id": service,
            "LoadState": load,
            "ActiveState": active,
            "SubState": sub,
            "Result": result,
            "ExecMainStatus": exec_status,
            "UnitFileState": unit,
            "ActiveEnterTimestamp": "Sat 2026-07-04 19:22:56 UTC",
            "InactiveEnterTimestamp": "",
        },
    )


def healthy_states() -> list[checker.ServiceState]:
    return [
        service_state("openclaw.service"),
    ]


def run_main(
    argv: list[str],
    states: list[checker.ServiceState],
) -> tuple[int, str, str]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    with patch.object(runner.checker, "evaluate_services", return_value=states):
        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = runner.main(argv)
    return exit_code, stdout.getvalue(), stderr.getvalue()


class ServiceStateMonitorRunnerTests(unittest.TestCase):
    def test_runner_returns_zero_when_services_are_healthy(self) -> None:
        exit_code, stdout, stderr = run_main(
            ["--project", PROJECT_ID],
            healthy_states(),
        )

        model = json.loads(stdout)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertTrue(model["dry_run"])
        self.assertEqual(len(model["time_series"]), 4)

    def test_runner_returns_nonzero_when_one_service_is_unhealthy(self) -> None:
        states = [
            service_state(
                "openclaw.service",
                active="inactive",
                sub="dead",
            ),
        ]

        exit_code, stdout, stderr = run_main(
            ["--project", PROJECT_ID],
            states,
        )
        model = json.loads(stdout)

        self.assertEqual(exit_code, 1)
        self.assertEqual(stderr, "")
        self.assertTrue(model["dry_run"])

    def test_runner_output_is_valid_json_dry_run_model(self) -> None:
        exit_code, stdout, _stderr = run_main(
            ["--project", PROJECT_ID],
            healthy_states(),
        )

        model = json.loads(stdout)

        self.assertEqual(exit_code, 0)
        self.assertEqual(model["project"], PROJECT_ID)
        self.assertEqual(
            model["metric_prefix"],
            "custom.googleapis.com/openclaw/service_state",
        )
        self.assertIn("time_series", model)

    def test_runner_output_contains_expected_metric_types(self) -> None:
        _exit_code, stdout, _stderr = run_main(
            ["--project", PROJECT_ID],
            healthy_states(),
        )

        metric_types = {
            series["metric_type"]
            for series in json.loads(stdout)["time_series"]
        }

        self.assertEqual(
            metric_types,
            {
                "custom.googleapis.com/openclaw/service_state/healthy",
                "custom.googleapis.com/openclaw/service_state/available",
                "custom.googleapis.com/openclaw/service_state/active",
                "custom.googleapis.com/openclaw/service_state/running",
            },
        )

    def test_runner_output_labels_contain_only_service(self) -> None:
        _exit_code, stdout, _stderr = run_main(
            ["--project", PROJECT_ID],
            healthy_states(),
        )

        for series in json.loads(stdout)["time_series"]:
            self.assertEqual(sorted(series["labels"].keys()), ["service"])

    def test_runner_honors_strict(self) -> None:
        states = [
            service_state("openclaw.service", unit="disabled"),
        ]

        exit_code, stdout, stderr = run_main(
            ["--project", PROJECT_ID, "--strict"],
            states,
        )
        model = json.loads(stdout)
        values = {
            (
                series["labels"]["service"],
                series["metric_type"],
            ): series["value"]
            for series in model["time_series"]
        }

        self.assertEqual(exit_code, 1)
        self.assertEqual(stderr, "")
        self.assertEqual(
            values[
                (
                    "openclaw.service",
                    "custom.googleapis.com/openclaw/service_state/healthy",
                )
            ],
            0,
        )

    def test_runner_rejects_unsupported_service_through_argparse(self) -> None:
        stdout = io.StringIO()
        stderr = io.StringIO()

        with patch.object(runner.checker, "evaluate_services") as evaluate:
            with redirect_stdout(stdout), redirect_stderr(stderr):
                with self.assertRaises(SystemExit) as raised:
                    runner.main(["--project", PROJECT_ID, "--service", "ssh.service"])

        self.assertEqual(raised.exception.code, 2)
        evaluate.assert_not_called()
        self.assertEqual(stdout.getvalue(), "")

    def test_runner_does_not_call_cloud_monitoring_apis(self) -> None:
        with patch.object(runner.writer, "build_dry_run_model") as build_model:
            with patch.object(runner.writer, "write_time_series") as write_time_series:
                build_model.return_value = (
                    {
                        "dry_run": True,
                        "project": PROJECT_ID,
                        "metric_prefix": runner.writer.DEFAULT_METRIC_PREFIX,
                        "time_series": [],
                    }
                )
                exit_code, stdout, stderr = run_main(
                    ["--project", PROJECT_ID],
                    healthy_states(),
                )

        build_model.assert_called_once()
        write_time_series.assert_not_called()
        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertIn('"dry_run": true', stdout)

    def test_runner_write_mode_calls_cloud_monitoring_writer_once(self) -> None:
        with patch.object(runner.writer, "write_time_series") as write_time_series:
            with patch.object(runner.writer, "build_dry_run_model") as build_model:
                write_time_series.return_value = {
                    "dry_run": False,
                    "project": PROJECT_ID,
                    "metric_prefix": runner.writer.DEFAULT_METRIC_PREFIX,
                    "time_series_count": 4,
                }
                exit_code, stdout, stderr = run_main(
                    ["--project", PROJECT_ID, "--write"],
                    healthy_states(),
                )

        write_time_series.assert_called_once()
        build_model.assert_not_called()
        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        model = json.loads(stdout)
        self.assertFalse(model["dry_run"])
        self.assertEqual(model["time_series_count"], 4)

    def test_runner_write_mode_returns_nonzero_when_service_is_unhealthy(self) -> None:
        states = [
            service_state(
                "openclaw.service",
                active="inactive",
                sub="dead",
            ),
        ]

        with patch.object(runner.writer, "write_time_series") as write_time_series:
            write_time_series.return_value = {
                "dry_run": False,
                "project": PROJECT_ID,
                "metric_prefix": runner.writer.DEFAULT_METRIC_PREFIX,
                "time_series_count": 4,
            }
            exit_code, stdout, stderr = run_main(
                ["--project", PROJECT_ID, "--write"],
                states,
            )

        write_time_series.assert_called_once()
        self.assertEqual(exit_code, 1)
        self.assertEqual(stderr, "")
        self.assertIn('"dry_run": false', stdout)

    def test_runner_write_mode_reports_writer_errors_without_traceback(self) -> None:
        with patch.object(runner.writer, "write_time_series") as write_time_series:
            write_time_series.side_effect = runner.writer.ValidationError("bad payload")
            exit_code, stdout, stderr = run_main(
                ["--project", PROJECT_ID, "--write"],
                healthy_states(),
            )

        self.assertEqual(exit_code, 1)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr, "error: bad payload\n")

    def test_runner_does_not_call_cloud_monitoring_apis_without_write(self) -> None:
        with patch.object(runner.writer, "build_dry_run_model") as build_model:
            build_model.return_value = (
                {
                    "dry_run": True,
                    "project": PROJECT_ID,
                    "metric_prefix": runner.writer.DEFAULT_METRIC_PREFIX,
                    "time_series": [],
                }
            )
            exit_code, stdout, stderr = run_main(
                ["--project", PROJECT_ID],
                healthy_states(),
            )

        build_model.assert_called_once()
        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertIn('"dry_run": true', stdout)

    def test_runner_does_not_propagate_raw_or_sensitive_fields(self) -> None:
        state = service_state("openclaw.service")
        state.properties.update(
            {
                "Environment": "SECRET=do-not-print",
                "ExecStart": "/bin/openclaw --token secret",
                "LogLine": "raw log payload",
                "SecretValue": "secret",
            }
        )

        exit_code, stdout, stderr = run_main(
            ["--project", PROJECT_ID],
            [state],
        )

        serialized = stdout + stderr

        self.assertEqual(exit_code, 0)
        self.assertNotIn("SECRET", serialized)
        self.assertNotIn("ExecStart", serialized)
        self.assertNotIn("command", serialized)
        self.assertNotIn("raw log payload", serialized)
        self.assertNotIn("SecretValue", serialized)
        self.assertNotIn("secret", serialized)


if __name__ == "__main__":
    unittest.main()
