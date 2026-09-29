from __future__ import annotations


def normalize_markdown(text: str) -> str:
    return (
        text.removeprefix("\ufeff")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
    )


def _parse_heading(line: str) -> tuple[int, str] | None:
    stripped = line.strip()

    if not stripped.startswith("#"):
        return None

    level = 0

    for char in stripped:
        if char == "#":
            level += 1
        else:
            break

    if level < 1 or level > 6:
        return None

    remainder = stripped[level:].strip()

    if not remainder:
        return None

    return level, remainder


def section_body(
    text: str,
    heading: str,
    *,
    level: int | None = None,
) -> str | None:
    lines = normalize_markdown(text).splitlines()

    target = heading.strip().casefold()

    start_index: int | None = None
    target_level: int | None = None

    for index, line in enumerate(lines):
        parsed = _parse_heading(line)

        if parsed is None:
            continue

        current_level, title = parsed

        if title.casefold() != target:
            continue

        if level is not None and current_level != level:
            continue

        start_index = index + 1
        target_level = current_level
        break

    if start_index is None or target_level is None:
        return None

    body: list[str] = []

    for line in lines[start_index:]:
        parsed = _parse_heading(line)

        if parsed is not None:
            current_level, _ = parsed

            if current_level <= target_level:
                break

        body.append(line)

    result = "\n".join(body).strip()

    if not result or result == "-":
        return None

    return result


def first_content_line(
    text: str,
    heading: str,
    *,
    level: int | None = None,
) -> str | None:
    body = section_body(
        text,
        heading,
        level=level,
    )

    if body is None:
        return None

    for line in body.splitlines():
        value = line.strip()

        if value and value != "-":
            return value

    return None


def subsection_values(
    text: str,
    parent_heading: str,
) -> dict[str, str]:
    body = section_body(
        text,
        parent_heading,
        level=2,
    )

    if body is None:
        return {}

    result: dict[str, str] = {}

    current_heading: str | None = None

    for line in body.splitlines():
        parsed = _parse_heading(line)

        if parsed is not None:
            level, title = parsed

            if level == 3:
                current_heading = title

            continue

        value = line.strip()

        if (
            current_heading is not None
            and value
            and value != "-"
        ):
            result[current_heading] = value
            current_heading = None

    return result
