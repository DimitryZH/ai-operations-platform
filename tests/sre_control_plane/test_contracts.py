from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

import pytest
from pydantic import ValidationError

from sre_control_plane.contracts import InvestigationRequest, InvestigationResult, ResultStatus

ROOT = Path(__file__).resolve().parents[2]


def load_example(name: str) -> dict:
    return json.loads((ROOT / "examples" / name).read_text(encoding="utf-8"))


def test_canonical_request_example_validates() -> None:
    request = InvestigationRequest.model_validate(load_example("sre-investigation-request.json"))

    assert request.schema_version == "1.0"
    assert request.scope.namespace == "online-shop-stage"
    assert request.scope.workload == "frontend"


def test_canonical_result_example_validates() -> None:
    result = InvestigationResult.model_validate(load_example("sre-investigation-result.json"))

    assert result.schema_version == "1.0"
    assert result.status is ResultStatus.SUCCEEDED
    assert result.human_review.required is True


def test_request_rejects_unsupported_capability() -> None:
    payload = load_example("sre-investigation-request.json")
    payload["requested_capabilities"].append("kubernetes.write")

    with pytest.raises(ValidationError, match="accepted MVP capability set"):
        InvestigationRequest.model_validate(payload)


def test_request_rejects_out_of_scope_workload() -> None:
    payload = load_example("sre-investigation-request.json")
    payload["scope"]["workload"] = "backend"

    with pytest.raises(ValidationError):
        InvestigationRequest.model_validate(payload)


def test_request_rejects_excessive_time_range() -> None:
    payload = load_example("sre-investigation-request.json")
    payload["scope"]["time_range"]["end"] = "2026-08-13T16:30:00Z"

    with pytest.raises(ValidationError, match="60 minutes"):
        InvestigationRequest.model_validate(payload)


def test_request_rejects_unsafe_private_reference() -> None:
    payload = load_example("sre-investigation-request.json")
    payload["source"]["reference"] = "http://127.0.0.1:9090/query?token=secret"

    with pytest.raises(ValidationError, match="unsafe"):
        InvestigationRequest.model_validate(payload)


def test_partial_result_is_schema_valid_when_limitations_are_explicit() -> None:
    payload = deepcopy(load_example("sre-investigation-result.json"))
    payload["status"] = "partial"
    payload["summary"] = "Partial evidence was collected but diagnosis completeness is not claimed."

    result = InvestigationResult.model_validate(payload)

    assert result.status is ResultStatus.PARTIAL
    assert result.limitations


def test_result_rejects_missing_evidence_reference() -> None:
    payload = load_example("sre-investigation-result.json")
    payload["findings"][0]["evidence_ids"].append("missing-evidence")

    with pytest.raises(ValidationError, match="missing evidence IDs"):
        InvestigationResult.model_validate(payload)
