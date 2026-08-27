from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from sre_control_plane.contracts import first_unsafe_string

EVIDENCE_CONTENT_TYPE = "application/json"
EVIDENCE_RETENTION_POLICY = "local-development-30d"


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


class EvidenceStore(Protocol):
    def store(self, package: EvidencePackage) -> StoredEvidence: ...


def build_evidence_package(payload: dict) -> EvidencePackage:
    unsafe_value = first_unsafe_string(payload)
    if unsafe_value is not None:
        raise EvidenceStoreError("evidence package contains unsafe content")
    content = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return EvidencePackage(
        payload=payload,
        content=content,
        sha256=hashlib.sha256(content).hexdigest(),
    )


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
