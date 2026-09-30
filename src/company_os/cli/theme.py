from __future__ import annotations

from textual.theme import Theme


DEFAULT_INTERFACE_THEME = "default"
HACKER_INTERFACE_THEME = "hacker"

SUPPORTED_INTERFACE_THEMES = (
    DEFAULT_INTERFACE_THEME,
    HACKER_INTERFACE_THEME,
)

HACKER_TEXTUAL_THEME_NAME = "aico-hacker"

HACKER_BLACK = "#000000"
HACKER_NEON = "#39FF14"
HACKER_NEON_DIM = "#00A83C"
HACKER_WARNING = "#FFD700"
HACKER_ERROR = "#FF3131"


HACKER_THEME = Theme(
    name=HACKER_TEXTUAL_THEME_NAME,
    primary=HACKER_NEON,
    secondary=HACKER_NEON_DIM,
    accent=HACKER_NEON,
    foreground=HACKER_NEON,
    background=HACKER_BLACK,
    surface=HACKER_BLACK,
    panel=HACKER_BLACK,
    boost=HACKER_BLACK,
    warning=HACKER_WARNING,
    error=HACKER_ERROR,
    success=HACKER_NEON,
    dark=True,
    variables={
        "block-cursor-foreground": HACKER_BLACK,
        "block-cursor-background": HACKER_NEON,
        "block-cursor-text-style": "bold",
        "footer-key-foreground": HACKER_NEON,
        "footer-description-foreground": HACKER_NEON_DIM,
        "input-selection-background": HACKER_NEON,
        "scrollbar": HACKER_NEON_DIM,
        "scrollbar-hover": HACKER_NEON,
        "scrollbar-active": HACKER_NEON,
        "border": HACKER_NEON,
        "border-blurred": HACKER_NEON_DIM,
    },
)


def normalize_interface_theme(
    value: str | None,
) -> str:
    if value in SUPPORTED_INTERFACE_THEMES:
        return str(value)

    return DEFAULT_INTERFACE_THEME


def next_interface_theme(
    value: str,
) -> str:
    current = normalize_interface_theme(
        value
    )

    index = (
        SUPPORTED_INTERFACE_THEMES.index(
            current
        )
    )

    return SUPPORTED_INTERFACE_THEMES[
        (
            index + 1
        )
        % len(
            SUPPORTED_INTERFACE_THEMES
        )
    ]


def is_hacker_interface(
    value: str | None,
) -> bool:
    return (
        normalize_interface_theme(value)
        == HACKER_INTERFACE_THEME
    )


def sync_hacker_screen_class(
    screen,
) -> None:
    app = getattr(
        screen,
        "app",
        None,
    )

    theme = getattr(
        app,
        "interface_theme",
        DEFAULT_INTERFACE_THEME,
    )

    if is_hacker_interface(theme):
        screen.add_class(
            "hacker-mode"
        )
    else:
        screen.remove_class(
            "hacker-mode"
        )


def terminal_navigation_label(
    index: int,
    label: str,
) -> str:
    return (
        f"{index:02d} // "
        f"{label.upper()}"
    )


def terminal_content_title(
    label: str,
) -> str:
    return f">_ {label.upper()}"


def terminal_section_title(
    label: str,
) -> str:
    return f"// {label.upper()}"


def terminal_header_title() -> str:
    return "AI COMPANY OS // CONTROL NODE"


def terminal_sub_title(
    project_name: str,
) -> str:
    return (
        f"{project_name} // ONLINE"
    )


def interface_theme_label(
    value: str,
) -> str:
    normalized = normalize_interface_theme(
        value
    )

    if normalized == HACKER_INTERFACE_THEME:
        return "Hacker"

    return "Default"
