from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Protocol


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


class Publisher(Protocol):
    def publish(self, request: PublicationRequest) -> PublicationReceipt: ...


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
