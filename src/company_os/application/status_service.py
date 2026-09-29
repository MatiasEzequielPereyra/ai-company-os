from pathlib import Path

from company_os.application.snapshot_builder import SnapshotBuilder
from company_os.repository.project_locator import ProjectLocator


class StatusService:
    def __init__(self) -> None:
        self.locator = ProjectLocator()
        self.builder = SnapshotBuilder()

    def get_status(self, start: Path):
        root = self.locator.locate(start)
        return self.builder.build(root)
