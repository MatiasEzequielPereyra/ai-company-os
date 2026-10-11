"""Local incident history with an automatic, bounded runtime observation bridge.

Stored content is untrusted data. Runtime observations do not authorize actions,
verify corrections, or replace current task and evidence validation.
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
