from __future__ import annotations

import hashlib
import json
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import quote, urlparse

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from sre_control_plane.contracts import first_unsafe_string

EVIDENCE_CONTENT_TYPE = "application/json"
LOCAL_EVIDENCE_RETENTION_POLICY = "local-development-30d"
GCS_EVIDENCE_RETENTION_POLICY = "gcs-evidence-bucket-30d"
EVIDENCE_RETENTION_POLICY = LOCAL_EVIDENCE_RETENTION_POLICY
MAX_EVIDENCE_PACKAGE_BYTES = 256 * 1024
MAX_EVIDENCE_COLLECTION_ITEMS = 100
GCS_EVIDENCE_OBJECT_PREFIX = "evidence/sha256"

_GCP_PROJECT_ID_PATTERN = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
_GCS_BUCKET_NAME_PATTERN = re.compile(
    r"^(?!goog)(?!.*\.\.)(?!.*--)[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$"
)
_GCS_METADATA_KEY_PATTERN = re.compile(r"^[a-z0-9_-]{1,64}$")
_GCS_METADATA_VALUE_PATTERN = re.compile(r"^[A-Za-z0-9._:/=-]{1,128}$")


class EvidenceStoreError(RuntimeError):
    pass


class TerminalEvidenceStoreError(EvidenceStoreError):
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
    """Canonical runtime contract for a bounded evidence-store response."""

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
        if parsed.scheme not in {"local", "gs"}:
            raise ValueError("artifact_uri must use an approved evidence scheme")
        if parsed.scheme == "local" and parsed.netloc != "evidence":
            raise ValueError("local artifact_uri must use the local://evidence authority")
        if parsed.scheme == "gs" and not _valid_gcs_bucket_name(parsed.netloc):
            raise ValueError("gcs artifact_uri must use a safe bucket name")
        if not parsed.path.endswith(".json"):
            raise ValueError("artifact_uri must reference a bounded JSON evidence artifact")
        if ".." in parsed.path or parsed.query or parsed.fragment:
            raise ValueError("artifact_uri contains unsafe components")
        return value

    @model_validator(mode="after")
    def validate_evidence_policy(self) -> "StoredEvidenceContract":
        if self.content_type != EVIDENCE_CONTENT_TYPE:
            raise ValueError("unexpected evidence content type")
        if self.sanitization_status != "SANITIZED":
            raise ValueError("evidence must be sanitized")
        parsed = urlparse(self.artifact_uri)
        if parsed.scheme == "local":
            if self.retention_policy != LOCAL_EVIDENCE_RETENTION_POLICY:
                raise ValueError("unexpected local evidence retention policy")
            if not parsed.path.startswith("/evidence-"):
                raise ValueError("local artifact_uri must reference a bounded evidence artifact")
        elif parsed.scheme == "gs":
            if self.retention_policy != GCS_EVIDENCE_RETENTION_POLICY:
                raise ValueError("unexpected gcs evidence retention policy")
            if not parsed.path.startswith(f"/{GCS_EVIDENCE_OBJECT_PREFIX}/"):
                raise ValueError("gcs artifact_uri must reference the bounded evidence prefix")
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
    if validated.artifact_uri != _expected_artifact_uri(validated.artifact_uri, package.sha256):
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
        try:
            with target.open("xb") as artifact_file:
                artifact_file.write(package.content)
        except FileExistsError:
            # A concurrent local writer may have created the file but not yet
            # completed its bounded write. Never accept different content.
            for _ in range(10):
                if target.read_bytes() == package.content:
                    break
                time.sleep(0.01)
            else:
                raise EvidenceStoreError("existing evidence artifact has different content")
        return StoredEvidence(
            artifact_uri=f"local://evidence/{filename}",
            sha256=package.sha256,
            content_type=EVIDENCE_CONTENT_TYPE,
            sanitization_status="SANITIZED",
            retention_policy=LOCAL_EVIDENCE_RETENTION_POLICY,
        )


class GcsEvidenceStore:
    """Bounded Cloud Storage adapter for the reviewed private GCP runtime."""

    def __init__(self, project_id: str, bucket_name: str, client: Any | None = None) -> None:
        if not _valid_gcp_project_id(project_id):
            raise TerminalEvidenceStoreError("GCS evidence project_id is missing or malformed")
        if not _valid_gcs_bucket_name(bucket_name):
            raise TerminalEvidenceStoreError("GCS evidence bucket_name is missing or malformed")
        if not bucket_name.startswith(f"{project_id}-sre-cp-") or not bucket_name.endswith("-evidence"):
            raise TerminalEvidenceStoreError("GCS evidence bucket does not match the reviewed project boundary")

        self._project_id = project_id
        self._bucket_name = bucket_name
        self._client = client if client is not None else _default_storage_client(project_id)
        self._bucket = self._client.bucket(bucket_name)

    @property
    def bucket_name(self) -> str:
        return self._bucket_name

    def store(self, package: EvidencePackage) -> StoredEvidence:
        _validate_evidence_package(package)
        object_name = gcs_evidence_object_name(package.sha256)
        blob = self._bucket.blob(object_name)
        metadata = _gcs_object_metadata(package)
        try:
            blob.metadata = metadata
            blob.upload_from_string(
                package.content,
                content_type=EVIDENCE_CONTENT_TYPE,
                if_generation_match=0,
            )
        except Exception as exc:
            if not _is_generation_precondition_failure(exc):
                raise EvidenceStoreError("GCS evidence storage unavailable") from exc
            _verify_existing_gcs_object(self._existing_blob(object_name), package)
        else:
            _verify_existing_gcs_object(self._existing_blob(object_name), package)

        return StoredEvidence(
            artifact_uri=gcs_evidence_artifact_uri(self._bucket_name, package.sha256),
            sha256=package.sha256,
            content_type=EVIDENCE_CONTENT_TYPE,
            sanitization_status="SANITIZED",
            retention_policy=GCS_EVIDENCE_RETENTION_POLICY,
        )

    def _existing_blob(self, object_name: str) -> Any:
        get_blob = getattr(self._bucket, "get_blob", None)
        if callable(get_blob):
            existing_blob = get_blob(object_name)
            if existing_blob is None:
                raise EvidenceStoreError("GCS evidence readback failed")
            return existing_blob
        return self._bucket.blob(object_name)


def gcs_evidence_object_name(sha256: str) -> str:
    if not re.fullmatch(r"[a-f0-9]{64}", sha256):
        raise TerminalEvidenceStoreError("invalid evidence object identity")
    return f"{GCS_EVIDENCE_OBJECT_PREFIX}/{sha256}.json"


def gcs_evidence_artifact_uri(bucket_name: str, sha256: str) -> str:
    if not _valid_gcs_bucket_name(bucket_name):
        raise TerminalEvidenceStoreError("invalid GCS evidence bucket name")
    return f"gs://{bucket_name}/{quote(gcs_evidence_object_name(sha256), safe='/')}"


def _validate_evidence_package(package: EvidencePackage) -> None:
    unsafe_value = first_unsafe_string(package.payload)
    if unsafe_value is not None:
        raise EvidenceStoreError("evidence package contains unsafe content")
    if hashlib.sha256(package.content).hexdigest() != package.sha256:
        raise TerminalEvidenceStoreError("evidence package integrity check failed")
    if len(package.content) > MAX_EVIDENCE_PACKAGE_BYTES:
        raise EvidenceStoreError("evidence package exceeds the bounded byte-size limit")
    _validate_collection_bounds(package.payload)


def _expected_artifact_uri(artifact_uri: str, sha256: str) -> str:
    parsed = urlparse(artifact_uri)
    if parsed.scheme == "local":
        return f"local://evidence/evidence-{sha256}.json"
    if parsed.scheme == "gs":
        return gcs_evidence_artifact_uri(parsed.netloc, sha256)
    raise EvidenceStoreError("evidence store returned an unsupported artifact scheme")


def _default_storage_client(project_id: str):
    try:
        from google.cloud import storage
    except ImportError as exc:
        raise EvidenceStoreError("google-cloud-storage is required for GCS evidence storage") from exc
    return storage.Client(project=project_id)


def _gcs_object_metadata(package: EvidencePackage) -> dict[str, str]:
    metadata = {
        "sha256": package.sha256,
        "sanitization_status": "SANITIZED",
        "content_type": EVIDENCE_CONTENT_TYPE,
        "identity": f"sha256:{package.sha256}",
    }
    for key, value in metadata.items():
        if not _GCS_METADATA_KEY_PATTERN.fullmatch(key):
            raise TerminalEvidenceStoreError("unsafe GCS evidence metadata key")
        if not _GCS_METADATA_VALUE_PATTERN.fullmatch(value):
            raise TerminalEvidenceStoreError("unsafe GCS evidence metadata value")
    return metadata


def _verify_existing_gcs_object(blob: Any, package: EvidencePackage) -> None:
    try:
        content = blob.download_as_bytes()
    except Exception as exc:
        raise EvidenceStoreError("GCS evidence readback failed") from exc
    if content != package.content or hashlib.sha256(content).hexdigest() != package.sha256:
        raise TerminalEvidenceStoreError("existing GCS evidence object has different content")
    metadata = getattr(blob, "metadata", None) or {}
    if metadata:
        expected = _gcs_object_metadata(package)
        for key, value in expected.items():
            if metadata.get(key) != value:
                raise TerminalEvidenceStoreError("existing GCS evidence object has unexpected metadata")


def _is_generation_precondition_failure(exc: Exception) -> bool:
    return (
        getattr(exc, "code", None) == 412
        or getattr(exc, "status_code", None) == 412
        or exc.__class__.__name__ in {"PreconditionFailed", "PreconditionFailedError"}
    )


def _valid_gcp_project_id(value: str) -> bool:
    return bool(_GCP_PROJECT_ID_PATTERN.fullmatch(value))


def _valid_gcs_bucket_name(value: str) -> bool:
    if len(value) < 3 or len(value) > 63:
        return False
    if "/" in value or value.startswith("gs://"):
        return False
    return bool(_GCS_BUCKET_NAME_PATTERN.fullmatch(value))
