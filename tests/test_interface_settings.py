from company_os.cli.interface_settings import (
    InterfaceSettingsService,
)


def test_default_language_is_spanish(
    tmp_path,
):
    service = InterfaceSettingsService(
        tmp_path / "settings.json"
    )

    assert (
        service.load_language()
        == "es"
    )


def test_language_is_persisted(
    tmp_path,
):
    path = tmp_path / "settings.json"

    service = InterfaceSettingsService(
        path
    )

    service.save_language("en")

    reloaded = InterfaceSettingsService(
        path
    )

    assert (
        reloaded.load_language()
        == "en"
    )


def test_invalid_language_falls_back(
    tmp_path,
):
    path = tmp_path / "settings.json"

    path.write_text(
        '{"language": "invalid"}',
        encoding="utf-8",
    )

    service = InterfaceSettingsService(
        path
    )

    assert (
        service.load_language()
        == "es"
    )
