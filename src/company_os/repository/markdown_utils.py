from __future__ import annotations

import re
from datetime import datetime


def _normalize_markdown(text: str) -> str:
    """Normalize common text quirks without changing document semantics."""
    return text.lstrip("\ufeff").replace("\r\n", "\n").replace("\r", "\n")


def heading_section(text: str, heading: str) -> str | None:
    """Return the body of a level-2 Markdown section.

    The parser tolerates BOMs, CRLF, trailing heading whitespace and blank lines.
    It stops at the next level-2 heading while preserving level-3 subsections.
    """
    normalized = _normalize_markdown(text)
    pattern = rf"^##[ \t]+{re.escape(heading)}[ \t]*$\n(.*?)(?=^##[ \t]+|\Z)"
    match = re.search(pattern, normalized, flags=re.MULTILINE | re.DOTALL | re.IGNORECASE)
    if not match:
        return None
    value = match.group(1).strip()
    return value if value and value != "-" else None


def subsection_value(section: str | None, heading: str) -> str | None:
    """Return the first meaningful line under a level-3 heading."""
    if not section:
        return None
    normalized = _normalize_markdown(section)
    pattern = rf"^###[ \t]+{re.escape(heading)}[ \t]*$\n(.*?)(?=^###[ \t]+|\Z)"
    match = re.search(pattern, normalized, flags=re.MULTILINE | re.DOTALL | re.IGNORECASE)
    if not match:
        return None
    body = match.group(1).strip()
    if not body or body == "-":
        return None
    for line in body.splitlines():
        candidate = line.strip()
        if candidate and candidate != "-":
            return candidate
    return None


def metadata_value(text: str, key: str) -> str | None:
    normalized = _normalize_markdown(text)
    match = re.search(rf"^{re.escape(key)}:\s*(.*?)\s*$", normalized, flags=re.MULTILINE | re.IGNORECASE)
    if not match:
        return None
    value = match.group(1).strip()
    return value if value and value != "-" else None


def bullet_lines(section: str | None) -> list[str]:
    if not section:
        return []
    return [line[2:].strip() for line in section.splitlines() if line.strip().startswith("- ")]


def parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
