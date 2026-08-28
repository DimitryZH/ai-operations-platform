from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from sre_control_plane.contracts import first_unsafe_string

EVIDENCE_CONTENT_TYPE = "application/json"
EVIDENCE_RETENTION_POLICY = "local-development-30d"
MAX_EVIDENCE_PACKAGE_BYTES = 256 * 1024
MAX_EVIDENCE_COLLECTION_ITEMS = 100


class EvidenceStoreError(RuntimeError):
    pass


@dataclass(frozen=True)
class EvidencePackage:
    payload: dict
    content: bytes
    sha256: str


@dataclass(frozen=True)
class StoredEvidence:
    artifact_uri: str
    sha256: str
    content_type: str
    sanitization_status: str
    retention_policy: str


class StoredEvidenceContract(BaseModel):
    """Canonical runtime contract for a bounded local evidence-store response."""

    model_config = ConfigDict(extra="forbid", strict=True)

    artifact_uri: str = Field(min_length=1, max_length=512)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    content_type: str = Field(min_length=1, max_length=128)
    sanitization_status: str = Field(min_length=1, max_length=32)
    retention_policy: str = Field(min_length=1, max_length=128)

    @field_validator("artifact_uri")
    @classmethod
    def validate_artifact_uri(cls, value: str) -> str:
        parsed = urlparse(value)
        if parsed.scheme != "local" or parsed.netloc != "evidence":
            raise ValueError("artifact_uri must use the local://evidence scheme")
        if not parsed.path.startswith("/evidence-") or not parsed.path.endswith(".json"):
            raise ValueError("artifact_uri must reference a bounded evidence artifact")
        if ".." in parsed.path or parsed.query or parsed.fragment:
            raise ValueError("artifact_uri contains unsafe components")
        return value

    @model_validator(mode="after")
    def validate_local_evidence_policy(self) -> "StoredEvidenceContract":
        if self.content_type != EVIDENCE_CONTENT_TYPE:
            raise ValueError("unexpected evidence content type")
        if self.sanitization_status != "SANITIZED":
            raise ValueError("evidence must be sanitized")
        if self.retention_policy != EVIDENCE_RETENTION_POLICY:
            raise ValueError("unexpected evidence retention policy")
        return self


class EvidenceStore(Protocol):
    def store(self, package: EvidencePackage) -> StoredEvidence: ...


def build_evidence_package(payload: dict) -> EvidencePackage:
    unsafe_value = first_unsafe_string(payload)
    if unsafe_value is not None:
        raise EvidenceStoreError("evidence package contains unsafe content")
    content = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if len(content) > MAX_EVIDENCE_PACKAGE_BYTES:
        raise EvidenceStoreError("evidence package exceeds the bounded byte-size limit")
    _validate_collection_bounds(payload)
    return EvidencePackage(
        payload=payload,
        content=content,
        sha256=hashlib.sha256(content).hexdigest(),
    )


def validate_stored_evidence(value: object, package: EvidencePackage) -> StoredEvidence:
    if isinstance(value, StoredEvidence):
        raw_value = value.__dict__
    elif isinstance(value, dict):
        raw_value = value
    else:
        raise EvidenceStoreError("evidence store returned an invalid response type")
    try:
        validated = StoredEvidenceContract.model_validate(raw_value)
    except Exception as exc:
        raise EvidenceStoreError("evidence store returned invalid artifact metadata") from exc
    if validated.sha256 != package.sha256:
        raise EvidenceStoreError("evidence store returned an artifact with unexpected integrity")
    expected_uri = f"local://evidence/evidence-{package.sha256}.json"
    if validated.artifact_uri != expected_uri:
        raise EvidenceStoreError("evidence store returned an unexpected artifact reference")
    return StoredEvidence(**validated.model_dump())


def _validate_collection_bounds(value: object) -> None:
    if isinstance(value, dict):
        if len(value) > MAX_EVIDENCE_COLLECTION_ITEMS:
            raise EvidenceStoreError("evidence package exceeds the bounded collection limit")
        for nested in value.values():
            _validate_collection_bounds(nested)
    elif isinstance(value, list):
        if len(value) > MAX_EVIDENCE_COLLECTION_ITEMS:
            raise EvidenceStoreError("evidence package exceeds the bounded collection limit")
        for nested in value:
            _validate_collection_bounds(nested)


class LocalFilesystemEvidenceStore:
    """Bounded local adapter intended only for deterministic local development."""

    def __init__(self, root: Path) -> None:
        self._root = root.resolve()

    def store(self, package: EvidencePackage) -> StoredEvidence:
        unsafe_value = first_unsafe_string(package.payload)
        if unsafe_value is not None:
            raise EvidenceStoreError("evidence package contains unsafe content")
        if hashlib.sha256(package.content).hexdigest() != package.sha256:
            raise EvidenceStoreError("evidence package integrity check failed")
        if len(package.content) > MAX_EVIDENCE_PACKAGE_BYTES:
            raise EvidenceStoreError("evidence package exceeds the bounded byte-size limit")
        _validate_collection_bounds(package.payload)

        self._root.mkdir(parents=True, exist_ok=True)
        filename = f"evidence-{package.sha256}.json"
        target = (self._root / filename).resolve()
        if target.parent != self._root:
            raise EvidenceStoreError("evidence path escapes configured root")
        if target.exists() and target.read_bytes() != package.content:
            raise EvidenceStoreError("existing evidence artifact has different content")
        if not target.exists():
            target.write_bytes(package.content)
        return StoredEvidence(
            artifact_uri=f"local://evidence/{filename}",
            sha256=package.sha256,
            content_type=EVIDENCE_CONTENT_TYPE,
            sanitization_status="SANITIZED",
            retention_policy=EVIDENCE_RETENTION_POLICY,
        )
