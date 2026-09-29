from __future__ import annotations

import tomllib
from pathlib import Path


def test_prompt_toolkit_is_declared_as_runtime_dependency() -> None:
    pyproject = tomllib.loads(
        Path("pyproject.toml").read_text(encoding="utf-8")
    )
    dependencies = pyproject["project"]["dependencies"]

    normalized = [
        dependency.lower().replace("_", "-")
        for dependency in dependencies
    ]

    assert any(
        dependency.startswith("prompt-toolkit")
        for dependency in normalized
    )
