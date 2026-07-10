import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

from monitoring import service_state_metric_writer as writer


PROJECT_ID = "your-gcp-project-id"
SENSITIVE_STRINGS = (
    "OPERATOR_SECRET_TOKEN",
    "redacted-token-value",
    "redacted-chat-value",
    "redacted-callback-value",
    "notificationChannels/redacted",
    "raw log payload",
)


class FakeMetric:
    def __init__(self) -> None:
        self.type = ""
        self.labels = {}


class FakeResource:
    def __init__(self) -> None:
        self.type = ""
        self.labels = {}


class FakeEndTime:
    def __init__(self) -> None:
        self.seconds = 0


class FakeInterval:
    def __init__(self) -> None:
        self.end_time = FakeEndTime()


class FakeValue:
    def __init__(self) -> None:
        self.int64_value = None


class FakePoint:
    def __init__(self) -> None:
        self.interval = FakeInterval()
        self.value = FakeValue()


class FakeUnsetInterval:
    def __init__(self) -> None:
        self.end_time = None


class FakeUnsetPoint:
    def __init__(self) -> None:
        self.interval = FakeUnsetInterval()
        self.value = None


class FakeProtoTimeInterval:
    def __init__(self, payload) -> None:
        self.end_time = FakeEndTime()
        self.end_time.seconds = payload["end_time"]["seconds"]


class FakeProtoTypedValue:
    def __init__(self, payload) -> None:
        self.int64_value = payload["int64_value"]


class FakeTimeSeries:
    def __init__(self) -> None:
        self.metric = FakeMetric()
        self.resource = FakeResource()
        self.points = []


class FakeClient:
    def __init__(self) -> None:
        self.calls = []

    def create_time_series(self, *, name, time_series) -> None:
        self.calls.append(
            {
                "name": name,
                "time_series": time_series,
            }
        )


class FakeMonitoringV3:
    def __init__(self) -> None:
        self.client = FakeClient()
        self.TimeSeries = FakeTimeSeries
        self.Point = FakePoint

    def MetricServiceClient(self) -> FakeClient:
        return self.client


class FakeProtoMonitoringV3(FakeMonitoringV3):
    def __init__(self) -> None:
        super().__init__()
        self.Point = FakeUnsetPoint
        self.TimeInterval = FakeProtoTimeInterval
        self.TypedValue = FakeProtoTypedValue


def valid_payload() -> dict:
    return {
        "ok": True,
        "strict": False,
        "metrics": [
            {
                "name": "openclaw_service_state_healthy",
                "value": 1,
                "labels": {
                    "service": "openclaw.service",
                },
            },
            {
                "name": "openclaw_service_state_available",
                "value": 1,
                "labels": {
                    "service": "openclaw.service",
                },
            },
            {
                "name": "openclaw_service_state_active",
                "value": 1,
                "labels": {
                    "service": "openclaw.service",
                },
            },
            {
                "name": "openclaw_service_state_running",
                "value": 0,
                "labels": {
                    "service": "openclaw.service",
                },
            },
        ],
    }


def run_main(argv: list[str], stdin_text: str = "") -> tuple[int, str, str]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    with patch.object(writer.sys, "stdin", io.StringIO(stdin_text)):
        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = writer.main(argv)
    return exit_code, stdout.getvalue(), stderr.getvalue()


def serialized_series(time_series) -> str:
    safe = []
    for series in time_series:
        safe.append(
            {
                "metric_type": series.metric.type,
                "metric_labels": dict(series.metric.labels),
                "resource_type": series.resource.type,
                "resource_labels": dict(series.resource.labels),
                "points": [
                    {
                        "end_time_seconds": point.interval.end_time.seconds,
                        "value": point.value.int64_value,
                    }
                    for point in series.points
                ],
            }
        )
    return json.dumps(safe, sort_keys=True)


class ServiceStateMetricWriterTests(unittest.TestCase):
    def test_valid_metrics_json_converts_to_bounded_dry_run_model(self) -> None:
        model = writer.build_dry_run_model(valid_payload(), project=PROJECT_ID)

        self.assertTrue(model["dry_run"])
        self.assertEqual(model["project"], PROJECT_ID)
        self.assertEqual(
            model["metric_prefix"],
            "custom.googleapis.com/openclaw/service_state",
        )
        self.assertEqual(len(model["time_series"]), 4)
        self.assertEqual(
            model["time_series"][0],
            {
                "metric_type": "custom.googleapis.com/openclaw/service_state/healthy",
                "value": 1,
                "labels": {
                    "service": "openclaw.service",
                },
            },
        )
        for series in model["time_series"]:
            self.assertEqual(sorted(series["labels"].keys()), ["service"])
            self.assertIn(series["value"], {0, 1})

    def test_stdin_input_works_and_dry_run_is_default(self) -> None:
        exit_code, stdout, stderr = run_main(
            ["--project", PROJECT_ID],
            stdin_text=json.dumps(valid_payload()),
        )

        model = json.loads(stdout)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertTrue(model["dry_run"])
        self.assertEqual(len(model["time_series"]), 4)

    def test_input_file_input_works(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            input_path = Path(tmpdir) / "metrics.json"
            input_path.write_text(json.dumps(valid_payload()), encoding="utf-8")

            exit_code, stdout, stderr = run_main(
                [
                    "--project",
                    PROJECT_ID,
                    "--input-file",
                    str(input_path),
                ]
            )

        model = json.loads(stdout)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(model["project"], PROJECT_ID)

    def test_unknown_metric_name_fails_closed(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["name"] = "openclaw_service_state_unknown"

        with self.assertRaisesRegex(writer.ValidationError, "unsupported metric name"):
            writer.build_dry_run_model(payload, project=PROJECT_ID)

    def test_unknown_service_fails_closed(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["labels"]["service"] = "ssh.service"

        with self.assertRaisesRegex(writer.ValidationError, "unsupported service label"):
            writer.build_dry_run_model(payload, project=PROJECT_ID)

    def test_extra_label_fails_closed(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["labels"]["zone"] = "us-central1-a"

        with self.assertRaisesRegex(writer.ValidationError, "unsupported metric labels"):
            writer.build_dry_run_model(payload, project=PROJECT_ID)

    def test_unknown_label_fails_closed(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["labels"] = {"instance": "vm-1"}

        with self.assertRaisesRegex(writer.ValidationError, "unsupported metric labels"):
            writer.build_dry_run_model(payload, project=PROJECT_ID)

    def test_value_other_than_zero_or_one_fails_closed(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["value"] = 2

        with self.assertRaisesRegex(writer.ValidationError, "unsupported metric value"):
            writer.build_dry_run_model(payload, project=PROJECT_ID)

    def test_non_numeric_value_fails_closed(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["value"] = "1"

        with self.assertRaisesRegex(writer.ValidationError, "unsupported metric value"):
            writer.build_dry_run_model(payload, project=PROJECT_ID)

    def test_float_value_fails_closed(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["value"] = 1.0

        with self.assertRaisesRegex(writer.ValidationError, "unsupported metric value"):
            writer.build_dry_run_model(payload, project=PROJECT_ID)

    def test_raw_log_like_field_is_not_propagated(self) -> None:
        payload = valid_payload()
        payload["raw_log"] = "do not emit this line"

        exit_code, stdout, stderr = run_main(
            ["--project", PROJECT_ID],
            stdin_text=json.dumps(payload),
        )

        self.assertEqual(exit_code, 1)
        self.assertEqual(stdout, "")
        self.assertNotIn("do not emit this line", stderr)

    def test_token_chat_and_callback_like_fields_are_not_propagated(self) -> None:
        payload = valid_payload()
        payload["apiToken"] = "redacted-token-value"
        payload["operatorChat"] = "redacted-chat-value"
        payload["callback_url"] = "redacted-callback-value"

        exit_code, stdout, stderr = run_main(
            ["--project", PROJECT_ID],
            stdin_text=json.dumps(payload),
        )

        self.assertEqual(exit_code, 1)
        self.assertEqual(stdout, "")
        self.assertNotIn("redacted-token-value", stderr)
        self.assertNotIn("redacted-chat-value", stderr)
        self.assertNotIn("redacted-callback-value", stderr)

    def test_invalid_payload_is_rejected_before_loading_cloud_monitoring(self) -> None:
        payload = valid_payload()
        payload["metrics"][0]["name"] = "openclaw_service_state_unknown"

        with patch.object(
            writer,
            "load_monitoring_v3",
            side_effect=AssertionError("Cloud Monitoring import should not run"),
        ):
            with self.assertRaisesRegex(writer.ValidationError, "unsupported metric name"):
                writer.write_time_series(payload, project=PROJECT_ID)

    def test_write_builds_cloud_monitoring_time_series_after_validation(self) -> None:
        fake_monitoring = FakeMonitoringV3()

        result = writer.write_time_series(
            valid_payload(),
            project=PROJECT_ID,
            monitoring_v3=fake_monitoring,
        )

        self.assertFalse(result["dry_run"])
        self.assertEqual(result["time_series_count"], 4)
        self.assertEqual(len(fake_monitoring.client.calls), 1)
        call = fake_monitoring.client.calls[0]
        self.assertEqual(call["name"], f"projects/{PROJECT_ID}")
        self.assertEqual(len(call["time_series"]), 4)

    def test_generated_cloud_monitoring_series_are_bounded(self) -> None:
        fake_monitoring = FakeMonitoringV3()
        metrics = writer.validate_metrics(valid_payload())

        series = writer.build_cloud_monitoring_time_series(
            metrics,
            project=PROJECT_ID,
            monitoring_v3=fake_monitoring,
            timestamp_seconds=1234567890,
        )

        self.assertEqual(
            {item.metric.type for item in series},
            {
                "custom.googleapis.com/openclaw/service_state/healthy",
                "custom.googleapis.com/openclaw/service_state/available",
                "custom.googleapis.com/openclaw/service_state/active",
                "custom.googleapis.com/openclaw/service_state/running",
            },
        )
        for item in series:
            self.assertEqual(sorted(item.metric.labels.keys()), ["service"])
            self.assertIn(
                item.metric.labels["service"],
                {
                    "openclaw.service",
                },
            )
            self.assertEqual(item.resource.type, "global")
            self.assertEqual(item.resource.labels["project_id"], PROJECT_ID)
            self.assertEqual(len(item.points), 1)
            self.assertEqual(item.points[0].interval.end_time.seconds, 1234567890)
            self.assertIn(item.points[0].value.int64_value, {0, 1})

        serialized = serialized_series(series)
        for sensitive in SENSITIVE_STRINGS:
            self.assertNotIn(sensitive, serialized)

    def test_generated_series_handles_unset_proto_point_fields(self) -> None:
        fake_monitoring = FakeProtoMonitoringV3()
        metrics = writer.validate_metrics(valid_payload())

        series = writer.build_cloud_monitoring_time_series(
            metrics,
            project=PROJECT_ID,
            monitoring_v3=fake_monitoring,
            timestamp_seconds=1234567890,
        )

        self.assertEqual(len(series), 4)
        for item in series:
            self.assertEqual(item.points[0].interval.end_time.seconds, 1234567890)
            self.assertIn(item.points[0].value.int64_value, {0, 1})

    def test_write_flag_uses_mocked_cloud_monitoring_client(self) -> None:
        fake_monitoring = FakeMonitoringV3()

        with patch.object(writer, "load_monitoring_v3", return_value=fake_monitoring):
            exit_code, stdout, stderr = run_main(
                ["--project", PROJECT_ID, "--write"],
                stdin_text=json.dumps(valid_payload()),
            )

        model = json.loads(stdout)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stderr, "")
        self.assertFalse(model["dry_run"])
        self.assertEqual(model["time_series_count"], 4)
        self.assertEqual(len(fake_monitoring.client.calls), 1)


if __name__ == "__main__":
    unittest.main()
