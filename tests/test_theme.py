from company_os.cli.theme import (
    DEFAULT_INTERFACE_THEME,
    HACKER_BLACK,
    HACKER_INTERFACE_THEME,
    HACKER_NEON,
    HACKER_TEXTUAL_THEME_NAME,
    HACKER_THEME,
    SUPPORTED_INTERFACE_THEMES,
    interface_theme_label,
    is_hacker_interface,
    next_interface_theme,
    normalize_interface_theme,
    terminal_content_title,
    terminal_header_title,
    terminal_navigation_label,
    terminal_section_title,
    terminal_sub_title,
    sync_hacker_screen_class,
)


def test_default_theme_stays_default():
    assert (
        DEFAULT_INTERFACE_THEME
        == "default"
    )

    assert (
        SUPPORTED_INTERFACE_THEMES[0]
        == DEFAULT_INTERFACE_THEME
    )


def test_hacker_theme_is_optional_second_theme():
    assert (
        HACKER_INTERFACE_THEME
        == "hacker"
    )

    assert (
        SUPPORTED_INTERFACE_THEMES
        == (
            "default",
            "hacker",
        )
    )


def test_invalid_theme_normalizes_to_default():
    assert (
        normalize_interface_theme(
            "unknown"
        )
        == "default"
    )


def test_theme_cycle_wraps():
    assert (
        next_interface_theme(
            "default"
        )
        == "hacker"
    )

    assert (
        next_interface_theme(
            "hacker"
        )
        == "default"
    )


def test_theme_labels_are_ascii_safe():
    for value in (
        "default",
        "hacker",
    ):
        assert (
            interface_theme_label(
                value
            ).isascii()
        )


def test_hacker_textual_theme_identity():
    assert (
        HACKER_THEME.name
        == HACKER_TEXTUAL_THEME_NAME
    )


def test_hacker_theme_uses_pure_black_and_neon_green():
    assert HACKER_BLACK == "#000000"
    assert HACKER_NEON == "#39FF14"

    assert (
        HACKER_THEME.variables[
            "block-cursor-foreground"
        ]
        == HACKER_BLACK
    )
    assert (
        HACKER_THEME.variables[
            "block-cursor-background"
        ]
        == HACKER_NEON
    )
    assert (
        HACKER_THEME.variables["border"]
        == HACKER_NEON
    )


def test_hacker_mode_detection_is_explicit():
    assert is_hacker_interface("hacker")
    assert not is_hacker_interface("default")
    assert not is_hacker_interface("invalid")


def test_terminal_chrome_is_ascii_safe():
    values = (
        terminal_navigation_label(
            1,
            "Resumen",
        ),
        terminal_content_title(
            "Resumen",
        ),
        terminal_section_title(
            "Node status",
        ),
        terminal_header_title(),
        terminal_sub_title(
            "Vendify",
        ),
    )

    assert values == (
        "01 // RESUMEN",
        ">_ RESUMEN",
        "// NODE STATUS",
        "AI COMPANY OS // CONTROL NODE",
        "Vendify // ONLINE",
    )

    for value in values:
        assert value.isascii()


def test_hacker_keyboard_highlight_is_white_on_green():
    from company_os.cli.tui import (
        AICompanyTUI,
    )

    css = AICompanyTUI.CSS

    assert (
        "ListItem.-highlight"
        in css
    )
    assert (
        "ListItem.-highlight Label"
        in css
    )
    assert (
        "ListItem.-hovered"
        in css
    )
    assert (
        "ListItem.--highlight"
        not in css
    )
    assert (
        "ListItem:hover"
        not in css
    )
    assert (
        "color: white;"
        in css
    )
    assert (
        "background: $secondary;"
        in css
    )
    assert (
        "outline: solid $accent;"
        not in css
    )


def test_screen_class_sync_tracks_interface_theme():
    class AppStub:
        interface_theme = "hacker"

    class ScreenStub:
        def __init__(self):
            self.app = AppStub()
            self.classes = set()

        def add_class(
            self,
            name,
        ):
            self.classes.add(name)

        def remove_class(
            self,
            name,
        ):
            self.classes.discard(name)

    screen = ScreenStub()

    sync_hacker_screen_class(
        screen
    )

    assert (
        "hacker-mode"
        in screen.classes
    )

    screen.app.interface_theme = (
        "default"
    )

    sync_hacker_screen_class(
        screen
    )

    assert (
        "hacker-mode"
        not in screen.classes
    )
