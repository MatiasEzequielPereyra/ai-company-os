from __future__ import annotations

import json
from pathlib import Path


class ConfigService:
    def __init__(self, config_dir: Path | None = None) -> None:
        self.config_dir = config_dir or (Path.home() / ".ai-company-os")
        self.config_path = self.config_dir / "config.json"
        self.history_path = self.config_dir / "history.txt"

        self.config_dir.mkdir(parents=True, exist_ok=True)

    def get_current_project(self) -> Path | None:
        if not self.config_path.exists():
            return None

        try:
            data = json.loads(
                self.config_path.read_text(
                    encoding="utf-8",
                    errors="replace",
                )
            )
        except (json.JSONDecodeError, OSError):
            return None

        value = data.get("current_project")

        if not value:
            return None

        return Path(value)

    def set_current_project(self, project: Path) -> None:
        project = project.resolve()

        data = {
            "current_project": str(project),
        }

        self.config_path.write_text(
            json.dumps(
                data,
                indent=2,
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

    def resolve_project(
        self,
        explicit: Path | None = None,
    ) -> Path:
        if explicit is not None:
            return explicit

        configured = self.get_current_project()

        if configured is not None:
            return configured

        return Path.cwd()
