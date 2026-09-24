from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TaskResultDetails:
    outcome: str = ""
    summary: str = ""
    blockers: str = ""
    recommended_next: str = ""
    provider: str = ""
    model: str = ""
    result_path: str = ""
    evidence_path: str = ""


class TaskResultService:
    def read_latest(
        self,
        project_root: str | Path,
        task_id: str,
    ) -> TaskResultDetails:
        root = Path(project_root).resolve()

        result_dir = (
            root
            / "docs"
            / "engineering"
            / "results"
        )

        result_path: Path | None = None
        result_text = ""

        if result_dir.exists():
            candidates = sorted(
                result_dir.glob(
                    f"{task_id}-result-*.md"
                ),
                key=lambda item: item.name,
                reverse=True,
            )

            if candidates:
                result_path = candidates[0]
                result_text = result_path.read_text(
                    encoding="utf-8-sig"
                )

        evidence_path = (
            root
            / "docs"
            / "engineering"
            / "writable-evidence"
            / f"{task_id}.md"
        )

        evidence_text = ""

        if evidence_path.exists():
            evidence_text = evidence_path.read_text(
                encoding="utf-8-sig"
            )

        return TaskResultDetails(
            outcome=self._field(
                result_text,
                "Outcome",
            ),
            summary=self._section(
                result_text,
                "Summary",
            ),
            blockers=self._section(
                result_text,
                "Blockers",
            ),
            recommended_next=self._section(
                result_text,
                "Recommended Next",
            ),
            provider=(
                self._field(
                    evidence_text,
                    "Provider",
                )
                or self._field(
                    result_text,
                    "Provider",
                )
            ),
            model=(
                self._field(
                    evidence_text,
                    "Model",
                )
                or self._field(
                    result_text,
                    "Model",
                )
            ),
            result_path=(
                str(result_path)
                if result_path
                else ""
            ),
            evidence_path=(
                str(evidence_path)
                if evidence_path.exists()
                else ""
            ),
        )

    def _field(
        self,
        content: str,
        key: str,
    ) -> str:
        if not content:
            return ""

        match = re.search(
            rf"(?mi)^\s*(?:-\s*)?"
            rf"{re.escape(key)}:\s*(.+?)\s*$",
            content,
        )

        if not match:
            return ""

        return match.group(1).strip()

    def _section(
        self,
        content: str,
        heading: str,
    ) -> str:
        if not content:
            return ""

        match = re.search(
            rf"(?ms)^##\s+"
            rf"{re.escape(heading)}\s*$"
            rf"\n(.*?)(?=^##\s+|\Z)",
            content,
        )

        if not match:
            return ""

        return match.group(1).strip()
