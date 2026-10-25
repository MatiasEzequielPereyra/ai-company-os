"""Immutable synthetic-only codec records; no operational authority."""

from dataclasses import dataclass, field
from types import MappingProxyType
from .contracts import ContractError


def freeze(value):
    if type(value) is dict:
        return MappingProxyType({k: freeze(v) for k, v in value.items()})
    if type(value) is list:
        return tuple(freeze(v) for v in value)
    return value


@dataclass(frozen=True)
class S1SyntheticLimits:
    piece_bytes: int
    total_bytes: int
    depth: int
    items: int
    pieces: int
    events: int

    def __post_init__(self):
        for name, ceiling in (
            ("piece_bytes", 8388608),
            ("total_bytes", 33554432),
            ("depth", 12),
            ("items", 256),
            ("pieces", 64),
            ("events", 256),
        ):
            v = getattr(self, name)
            if type(v) is not int or not 0 < v <= ceiling:
                raise ContractError("S1_LIMIT_CONFIGURATION")


@dataclass(frozen=True)
class DecodedPiece:
    raw: bytes
    digest: str
    kind: str
    value: object


@dataclass(frozen=True)
class ConsistencyReport:
    package_sha256: str
    package_kind: str
    wire_provenance: str
    scope: str = field(default="SIMULATION", init=False)
    operational: bool = field(default=False, init=False)
    unauthenticated_audit: bool = field(default=True, init=False)
