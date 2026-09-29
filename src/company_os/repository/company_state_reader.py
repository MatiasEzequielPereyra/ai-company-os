from pathlib import Path

from company_os.domain.models import GateState, WorkflowPhase
from company_os.repository.markdown_sections import (
    first_content_line,
    subsection_values,
)


class CompanyStateReader:
    GATES = [
        "PRODUCT",
        "ARCHITECTURE",
        "IMPLEMENTATION",
        "REVIEW",
        "QA",
        "SECURITY",
        "RELEASE",
        "FINAL",
    ]

    def read(self, root: Path) -> dict:
        path = root / ".codex" / "state" / "company-state.md"

        if not path.exists():
            return {
                "phase": None,
                "objective": None,
                "gates": {},
                "source": str(path),
            }

        text = path.read_text(
            encoding="utf-8-sig",
            errors="replace",
        )

        phase_raw = first_content_line(
            text,
            "Current Project Phase",
            level=2,
        )

        phase = None

        if phase_raw:
            value = phase_raw.strip().upper()

            if value in WorkflowPhase._value2member_map_:
                phase = WorkflowPhase(value)

        objective = first_content_line(
            text,
            "Current Objective",
            level=2,
        )

        raw_gates = subsection_values(
            text,
            "Quality Gates",
        )

        normalized_gates = {
            name.strip().upper(): value.strip().upper()
            for name, value in raw_gates.items()
        }

        gates: dict[str, GateState] = {}

        for gate in self.GATES:
            value = normalized_gates.get(
                gate,
                "UNKNOWN",
            )

            if value in GateState._value2member_map_:
                gates[gate] = GateState(value)
            else:
                gates[gate] = GateState.UNKNOWN

        return {
            "phase": phase,
            "objective": objective,
            "gates": gates,
            "source": str(path),
        }
