from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Protocol
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, field_validator


class PublicationError(RuntimeError):
    pass


@dataclass(frozen=True)
class PublicationRequest:
    idempotency_key: str
    payload_sha256: str
    payload: dict


@dataclass(frozen=True)
class PublicationReceipt:
    reference: str


class PublicationReceiptContract(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    reference: str = Field(min_length=1, max_length=512)

    @field_validator("reference")
    @classmethod
    def validate_reference(cls, value: str) -> str:
        parsed = urlparse(value)
        if parsed.scheme != "fake" or parsed.netloc != "publication":
            raise ValueError("publication reference must use the fake://publication scheme")
        if not parsed.path.startswith("/") or len(parsed.path) != 17:
            raise ValueError("publication reference is malformed")
        if any(character not in "0123456789abcdef" for character in parsed.path[1:]):
            raise ValueError("publication reference is malformed")
        if parsed.query or parsed.fragment:
            raise ValueError("publication reference contains unsafe components")
        return value


class Publisher(Protocol):
    def publish(self, request: PublicationRequest) -> PublicationReceipt: ...


def validate_publication_receipt(value: object) -> PublicationReceipt:
    if isinstance(value, PublicationReceipt):
        raw_value = value.__dict__
    elif isinstance(value, dict):
        raw_value = value
    else:
        raise PublicationError("publisher returned an invalid response type")
    try:
        validated = PublicationReceiptContract.model_validate(raw_value)
    except Exception as exc:
        raise PublicationError("publisher returned an invalid publication receipt") from exc
    return PublicationReceipt(**validated.model_dump())


class FakePublisher:
    """Deterministic local publisher. It performs no GitHub or network writes."""

    def __init__(self) -> None:
        self._references: dict[str, str] = {}

    def publish(self, request: PublicationRequest) -> PublicationReceipt:
        reference = self._references.setdefault(
            request.idempotency_key,
            "fake://publication/" + hashlib.sha256(request.payload_sha256.encode()).hexdigest()[:16],
        )
        return PublicationReceipt(reference=reference)
