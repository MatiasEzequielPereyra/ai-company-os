from pathlib import Path

from company_os.repository.markdown_sections import first_content_line


class SprintReader:
    def read(self, root: Path) -> dict:
        path = root / ".codex" / "state" / "current-sprint.md"

        if not path.exists():
            return {
                "goal": None,
                "source": str(path),
            }

        text = path.read_text(
            encoding="utf-8-sig",
            errors="replace",
        )

        return {
            "goal": first_content_line(
                text,
                "Sprint Goal",
                level=2,
            ),
            "source": str(path),
        }
