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
