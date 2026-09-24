from company_os.cli.i18n import (
    DEFAULT_LANGUAGE,
    HELP_SECTION_IDS,
    help_section_content,
    navigation_label,
)


def test_default_language_is_spanish():
    assert DEFAULT_LANGUAGE == "es"


def test_navigation_changes_only_display_label():
    assert (
        navigation_label(
            "es",
            "overview",
        )
        == "Resumen"
    )

    assert (
        navigation_label(
            "en",
            "overview",
        )
        == "Overview"
    )


def test_internal_view_id_is_not_translated():
    view_id = "workflow"

    assert view_id == "workflow"

    assert (
        navigation_label(
            "es",
            view_id,
        )
        == "Workflow / DAG"
    )


def test_help_exists_in_both_languages():
    for section_id in HELP_SECTION_IDS:
        es_title, es_body = (
            help_section_content(
                "es",
                section_id,
            )
        )

        en_title, en_body = (
            help_section_content(
                "en",
                section_id,
            )
        )

        assert es_title
        assert es_body
        assert en_title
        assert en_body


def test_canonical_status_names_remain_literal():
    _, spanish = help_section_content(
        "es",
        "workflow",
    )

    for status in (
        "BACKLOG",
        "READY",
        "ACTIVE",
        "REVIEW",
        "QA",
        "SECURITY",
        "DONE",
        "BLOCKED",
    ):
        assert status in spanish



def _walk_strings(value):
    if isinstance(value, str):
        yield value
        return

    if isinstance(value, dict):
        for item in value.values():
            yield from _walk_strings(item)
        return

    if isinstance(value, (list, tuple)):
        for item in value:
            yield from _walk_strings(item)


def test_spanish_ui_is_ascii_safe():
    import company_os.cli.i18n as i18n

    sources = [
        i18n.NAVIGATION_LABELS["es"],
        i18n.HELP["es"],
        i18n.UI_TEXT["es"],
    ]

    for source in sources:
        for value in _walk_strings(source):
            assert value.isascii(), value


def test_spanish_ui_has_no_intraword_apostrophes():
    import re
    import company_os.cli.i18n as i18n

    sources = [
        i18n.NAVIGATION_LABELS["es"],
        i18n.HELP["es"],
        i18n.UI_TEXT["es"],
    ]

    pattern = re.compile(
        r"(?<=[A-Za-z])'(?=[A-Za-z])"
    )

    for source in sources:
        for value in _walk_strings(source):
            assert not pattern.search(value), value



def test_spanish_ui_text_is_ascii_safe():
    from company_os.cli import i18n

    def walk(value):
        if isinstance(value, str):
            yield value
            return

        if isinstance(value, dict):
            for item in value.values():
                yield from walk(item)
            return

        if isinstance(value, (tuple, list)):
            for item in value:
                yield from walk(item)

    sources = (
        i18n.NAVIGATION_LABELS["es"],
        i18n.HELP["es"],
        i18n.UI_TEXT["es"],
    )

    for source in sources:
        for value in walk(source):
            assert value.isascii(), value


def test_future_provider_names_do_not_change_core_contract():
    from company_os.cli import i18n

    text = i18n.UI_TEXT["es"]["providers_core_note"]

    assert "DeepSeek" in text
    assert "Grok / xAI" in text
    assert "Ollama" in text



def test_screen_text_languages_have_same_keys():
    from company_os.cli import i18n

    assert set(
        i18n.SCREEN_TEXT["es"]
    ) == set(
        i18n.SCREEN_TEXT["en"]
    )


def test_flow_text_languages_have_same_keys():
    from company_os.cli import i18n

    assert set(
        i18n.FLOW_TEXT["es"]
    ) == set(
        i18n.FLOW_TEXT["en"]
    )


def test_navigation_languages_have_same_keys():
    from company_os.cli import i18n

    assert set(
        i18n.NAVIGATION_LABELS["es"]
    ) == set(
        i18n.NAVIGATION_LABELS["en"]
    )



def test_ux_text_languages_have_same_keys():
    from company_os.cli import i18n

    assert set(
        i18n.UX_TEXT["es"]
    ) == set(
        i18n.UX_TEXT["en"]
    )


def test_spanish_ux_text_is_ascii_safe():
    from company_os.cli import i18n

    for value in i18n.UX_TEXT["es"].values():
        assert value.isascii(), value



def test_prefs_text_languages_have_same_keys():
    from company_os.cli import i18n

    assert set(
        i18n.PREFS_TEXT["es"]
    ) == set(
        i18n.PREFS_TEXT["en"]
    )


def test_spanish_prefs_text_is_ascii_safe():
    from company_os.cli import i18n

    for value in i18n.PREFS_TEXT["es"].values():
        assert value.isascii(), value
