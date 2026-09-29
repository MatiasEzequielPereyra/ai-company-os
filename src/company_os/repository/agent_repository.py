from __future__ import annotations

import tomllib
from pathlib import Path


DISPLAY_NAMES = {
    "ceo": "CEO / Orchestrator",
    "pm": "Product Manager",
    "cto": "CTO",
    "engineering_manager": "Engineering Manager",
    "backend": "Backend Engineer",
    "frontend": "Frontend Engineer",
    "devops": "DevOps Engineer",
    "qa": "QA Engineer",
    "security": "Security Engineer",
}


class AgentRepository:
    def list_agents(self, root: Path) -> list[dict]:
        path = root / ".codex" / "config.toml"
        if not path.exists():
            return []

        data = tomllib.loads(path.read_text(encoding="utf-8"))
        agents = data.get("agents", {})
        result = []
        for key, value in agents.items():
            if not isinstance(value, dict):
                continue
            result.append({
                "id": key.replace("_", "-"),
                "config_key": key,
                "display_name": DISPLAY_NAMES.get(key, key.replace("_", " ").title()),
                "description": value.get("description"),
            })
        return result
