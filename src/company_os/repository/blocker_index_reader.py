from pathlib import Path

from company_os.repository.markdown_utils import heading_section


class BlockerIndexReader:
    def read(self, root: Path) -> dict:
        path = root / ".codex" / "state" / "blockers.md"
        if not path.exists():
            return {"raw_active": None, "source": str(path)}
        text = path.read_text(encoding="utf-8", errors="replace")
        return {"raw_active": heading_section(text, "Active Blockers"), "source": str(path)}
