from company_os.cli import i18n


def test_ux3_languages_have_same_keys():
    assert set(
        i18n.UX3_TEXT["es"]
    ) == set(
        i18n.UX3_TEXT["en"]
    )


def test_spanish_ux3_is_ascii_safe():
    for value in (
        i18n.UX3_TEXT["es"].values()
    ):
        assert value.isascii(), value


def test_provider_and_model_labels_exist():
    assert (
        i18n.ui_text(
            "es",
            "pc_provider",
        )
        == "Provider"
    )

    assert (
        i18n.ui_text(
            "es",
            "pc_model",
        )
        == "Model"
    )
