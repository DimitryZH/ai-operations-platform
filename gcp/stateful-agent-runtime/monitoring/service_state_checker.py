"""Check bounded systemd service state without reading logs or environments."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable, Sequence


ALLOWED_PROPERTIES = (
    "Id",
    "LoadState",
    "ActiveState",
    "SubState",
    "Result",
    "ExecMainStatus",
    "UnitFileState",
    "ActiveEnterTimestamp",
    "InactiveEnterTimestamp",
)

DEFAULT_SERVICES = (
    "openclaw.service",
)

METRIC_NAMES = (
    "openclaw_service_state_healthy",
    "openclaw_service_state_available",
    "openclaw_service_state_active",
    "openclaw_service_state_running",
)

SYSTEMCTL_TIMEOUT_SECONDS = 5


@dataclass(frozen=True)
class ServiceState:
    service: str
    properties: dict[str, str]
    command_error: str | None = None

    @property
    def available(self) -> bool:
        return self.command_error is None and self.properties.get("LoadState") not in {
            "",
            "not-found",
            "error",
        }

    def is_healthy(self, *, strict: bool = False) -> bool:
        if not self.available:
            return False

        active_running = (
            self.properties.get("ActiveState") == "active"
            and self.properties.get("SubState") == "running"
        )
        if not active_running:
            return False

        if not strict:
            return True

        return (
            self.properties.get("LoadState") == "loaded"
            and self.properties.get("Result") == "success"
            and self.properties.get("ExecMainStatus", "0") in {"", "0"}
            and self.properties.get("UnitFileState") in {"enabled", "enabled-runtime"}
        )

    def reason(self, *, strict: bool = False) -> str:
        if self.command_error is not None:
            return self.command_error
        if not self.available:
            return "service_unavailable"
        if self.is_healthy(strict=strict):
            return "ok"
        if self.properties.get("ActiveState") != "active":
            return "inactive"
        if self.properties.get("SubState") != "running":
            return "not_running"
        if strict and self.properties.get("Result") != "success":
            return "non_success_result"
        if strict and self.properties.get("ExecMainStatus", "0") not in {"", "0"}:
            return "non_zero_exec_status"
        if strict and self.properties.get("UnitFileState") not in {"enabled", "enabled-runtime"}:
            return "not_enabled"
        return "unhealthy"

    def to_sanitized_dict(self, *, strict: bool = False) -> dict[str, object]:
        return {
            "service": self.service,
            "healthy": self.is_healthy(strict=strict),
            "reason": self.reason(strict=strict),
            "properties": {
                name: self.properties.get(name, "")
                for name in ALLOWED_PROPERTIES
            },
        }

    def to_metric_values(self, *, strict: bool = False) -> dict[str, int]:
        return {
            "openclaw_service_state_healthy": int(self.is_healthy(strict=strict)),
            "openclaw_service_state_available": int(self.available),
            "openclaw_service_state_active": int(
                self.properties.get("ActiveState") == "active"
            ),
            "openclaw_service_state_running": int(
                self.properties.get("SubState") == "running"
            ),
        }


def parse_systemctl_show(output: str) -> dict[str, str]:
    properties: dict[str, str] = {name: "" for name in ALLOWED_PROPERTIES}
    for raw_line in output.splitlines():
        if "=" not in raw_line:
            continue
        name, value = raw_line.split("=", 1)
        if name in properties:
            properties[name] = value.strip()
    return properties


def run_systemctl_show(service: str) -> ServiceState:
    command = [
        "systemctl",
        "show",
        service,
        "--no-pager",
    ]
    for property_name in ALLOWED_PROPERTIES:
        command.append(f"--property={property_name}")

    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=SYSTEMCTL_TIMEOUT_SECONDS,
        )
    except FileNotFoundError:
        return ServiceState(service=service, properties={}, command_error="systemctl_not_found")
    except subprocess.TimeoutExpired:
        return ServiceState(service=service, properties={}, command_error="systemctl_timeout")

    properties = parse_systemctl_show(completed.stdout)
    if completed.returncode != 0:
        return ServiceState(
            service=service,
            properties=properties,
            command_error="systemctl_failed",
        )

    return ServiceState(service=service, properties=properties)


def evaluate_services(services: Iterable[str]) -> list[ServiceState]:
    return [run_systemctl_show(service) for service in services]


def render_json(states: Sequence[ServiceState], *, strict: bool = False) -> str:
    payload = {
        "ok": all(state.is_healthy(strict=strict) for state in states),
        "strict": strict,
        "services": [state.to_sanitized_dict(strict=strict) for state in states],
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def render_metrics_json(states: Sequence[ServiceState], *, strict: bool = False) -> str:
    metrics = []
    for state in states:
        values = state.to_metric_values(strict=strict)
        for metric_name in METRIC_NAMES:
            metrics.append(
                {
                    "name": metric_name,
                    "value": values[metric_name],
                    "labels": {
                        "service": state.service,
                    },
                }
            )

    payload = {
        "ok": all(state.is_healthy(strict=strict) for state in states),
        "strict": strict,
        "metrics": metrics,
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def render_text(states: Sequence[ServiceState], *, strict: bool = False) -> str:
    lines = []
    for state in states:
        properties = state.properties
        status = "healthy" if state.is_healthy(strict=strict) else "unhealthy"
        lines.append(
            " ".join(
                [
                    state.service,
                    status,
                    f"reason={state.reason(strict=strict)}",
                    f"load={properties.get('LoadState', '')}",
                    f"active={properties.get('ActiveState', '')}",
                    f"sub={properties.get('SubState', '')}",
                    f"result={properties.get('Result', '')}",
                    f"exec={properties.get('ExecMainStatus', '')}",
                    f"unit={properties.get('UnitFileState', '')}",
                ]
            )
        )
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Check bounded systemd state for approved OpenClaw services."
    )
    parser.add_argument(
        "--service",
        action="append",
        choices=DEFAULT_SERVICES,
        help="Service to check. Repeat to check more than one. Defaults to approved services.",
    )
    parser.add_argument(
        "--format",
        choices=("json", "text", "metrics-json"),
        default="text",
        help="Output format.",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Also require loaded/enabled/success metadata.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    services = args.service or list(DEFAULT_SERVICES)
    states = evaluate_services(services)

    if args.format == "json":
        print(render_json(states, strict=args.strict))
    elif args.format == "metrics-json":
        print(render_metrics_json(states, strict=args.strict))
    else:
        print(render_text(states, strict=args.strict))

    return 0 if all(state.is_healthy(strict=args.strict) for state in states) else 1


if __name__ == "__main__":
    sys.exit(main())
