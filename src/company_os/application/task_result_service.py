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
    changed_paths: tuple[str, ...] = ()
    verification: str = ""
    retry_reason: str = ""


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
            changed_paths=self._bullet_section(
                evidence_text,
                "Changed Paths",
            ),
            verification=self._section(
                evidence_text,
                "Verification",
            ),
            retry_reason=self._retry_reason(
                root,
                task_id,
            ),
        )

    def _bullet_section(
        self,
        content: str,
        heading: str,
    ) -> tuple[str, ...]:
        section = self._section(
            content,
            heading,
        )

        if not section:
            return ()

        values = []

        for line in section.splitlines():
            value = line.strip()

            if value.startswith("- "):
                value = value[2:].strip()

            if value:
                values.append(value)

        return tuple(values)

    def _retry_reason(
        self,
        root: Path,
        task_id: str,
    ) -> str:
        review_dir = (
            root
            / "docs"
            / "engineering"
            / "reviews"
        )

        if review_dir.exists():
            reviews = sorted(
                review_dir.glob(
                    f"{task_id}-review-*.md"
                ),
                key=lambda item: item.name,
                reverse=True,
            )

            if reviews:
                recommendation = self._field(
                    reviews[0].read_text(
                        encoding="utf-8-sig"
                    ),
                    "Recommendation",
                )

                if recommendation == "CHANGES_REQUIRED":
                    return "CHANGES_REQUIRED"

        for folder, suffix, value in (
            ("qa", "qa", "QA FAIL"),
            ("security", "security", "SECURITY FAIL"),
            ("final-approvals", "final", "FINAL REJECT"),
        ):
            path = (
                root
                / "docs"
                / "engineering"
                / folder
                / f"{task_id}-{suffix}.md"
            )

            if not path.exists():
                continue

            text = path.read_text(
                encoding="utf-8-sig"
            )

            outcome = (
                self._field(text, "Outcome")
                or self._field(text, "Decision")
            )

            if outcome in {
                "FAIL",
                "REJECT",
            }:
                return value

        return ""

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
