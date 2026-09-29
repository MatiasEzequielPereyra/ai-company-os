from __future__ import annotations

from pathlib import Path

from company_os.application.runtime_adapter import (
    RuntimeAdapter,
    RuntimeSnapshot,
)
from company_os.application.status_service import StatusService


class RuntimeService:
    def __init__(self) -> None:
        self.status_service = StatusService()
        self.adapter = RuntimeAdapter()

    def get_runtime_source(
        self,
        project: Path,
    ) -> RuntimeSnapshot:
        snapshot = (
            self.status_service
            .get_status(project)
        )

        root = Path(
            snapshot.project.root
        )

        return self.adapter.inspect(
            root
        )