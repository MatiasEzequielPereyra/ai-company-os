"""Isolated, local error history for explicit operator use.

This package is deliberately not imported by the runtime, agents, or workflow
services. Stored incident content is untrusted data and must not be treated as
policy or instructions.
"""

from .store import (
    ErrorIntelligenceError,
    ErrorIntelligenceStore,
    IncidentEvent,
    Incident,
    IncidentObservation,
    InvalidIncidentError,
    StoreCorruptError,
    StoreBusyError,
    default_store_path,
)

__all__ = [
    "ErrorIntelligenceError",
    "ErrorIntelligenceStore",
    "IncidentEvent",
    "Incident",
    "IncidentObservation",
    "InvalidIncidentError",
    "StoreCorruptError",
    "StoreBusyError",
    "default_store_path",
]
