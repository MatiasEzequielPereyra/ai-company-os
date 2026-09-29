from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

from company_os.application.config_service import ConfigService


@dataclass
class RecentProject:
    name: str
    path: str

    def to_dict(self) -> dict:
        return asdict(self)


class ProjectService:
    def __init__(
        self,
        config_service=None,
        storage_root: Path | None = None,
    ) -> None:
        self.config = config_service or ConfigService()
        self.storage_root = (
            storage_root
            or Path.home() / ".ai-company-os"
        )
        self.storage_root.mkdir(
            parents=True,
            exist_ok=True,
        )

        self.recents_path = (
            self.storage_root
            / "projects.json"
        )

    def open_project(
        self,
        project: Path | str,
    ) -> Path:
        root = Path(project).expanduser().resolve()

        if not root.exists():
            raise FileNotFoundError(
                f"Project does not exist: {root}"
            )

        if not root.is_dir():
            raise ValueError(
                f"Project path is not a directory: {root}"
            )

        if not (
            (root / ".git").exists()
            or (root / "tasks").exists()
            or (root / ".codex").exists()
        ):
            raise ValueError(
                "The selected directory does not look "
                "like a Git or AI Company OS project."
            )

        self.config.set_current_project(root)
        self._register_recent(root)

        return root

    def list_recent(
        self,
    ) -> list[RecentProject]:
        if not self.recents_path.exists():
            return []

        try:
            raw = json.loads(
                self.recents_path.read_text(
                    encoding="utf-8"
                )
            )
        except (
            json.JSONDecodeError,
            OSError,
        ):
            return []

        result = []

        for item in raw:
            path = item.get("path")

            if not path:
                continue

            result.append(
                RecentProject(
                    name=(
                        item.get("name")
                        or Path(path).name
                    ),
                    path=path,
                )
            )

        return result

    def _register_recent(
        self,
        root: Path,
    ) -> None:
        projects = [
            project
            for project in self.list_recent()
            if Path(project.path) != root
        ]

        projects.insert(
            0,
            RecentProject(
                name=root.name,
                path=str(root),
            ),
        )

        projects = projects[:10]

        self.recents_path.write_text(
            json.dumps(
                [
                    project.to_dict()
                    for project in projects
                ],
                indent=2,
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )