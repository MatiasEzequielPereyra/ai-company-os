from pathlib import Path


class ProjectLocator:
    MARKERS = ("AGENTS.md", ".codex", "tasks")

    def locate(self, start: Path) -> Path:
        current = start.resolve()
        if current.is_file():
            current = current.parent

        for candidate in (current, *current.parents):
            score = sum((candidate / marker).exists() for marker in self.MARKERS)
            if score >= 2:
                return candidate

        raise FileNotFoundError("AI Company OS repository not found from current path")
