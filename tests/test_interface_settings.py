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


def test_default_theme_is_default(
    tmp_path,
):
    service = InterfaceSettingsService(
        tmp_path / "settings.json"
    )

    assert (
        service.load_theme()
        == "default"
    )


def test_theme_is_persisted(
    tmp_path,
):
    path = tmp_path / "settings.json"

    service = InterfaceSettingsService(
        path
    )

    service.save_theme("hacker")

    reloaded = InterfaceSettingsService(
        path
    )

    assert (
        reloaded.load_theme()
        == "hacker"
    )


def test_invalid_theme_falls_back(
    tmp_path,
):
    path = tmp_path / "settings.json"

    path.write_text(
        '{"language": "es", "theme": "invalid"}',
        encoding="utf-8",
    )

    service = InterfaceSettingsService(
        path
    )

    assert (
        service.load_theme()
        == "default"
    )


def test_language_save_preserves_theme(
    tmp_path,
):
    path = tmp_path / "settings.json"

    service = InterfaceSettingsService(
        path
    )

    service.save_theme("hacker")
    service.save_language("en")

    reloaded = InterfaceSettingsService(
        path
    )

    assert (
        reloaded.load_language()
        == "en"
    )
    assert (
        reloaded.load_theme()
        == "hacker"
    )


def test_theme_save_preserves_language(
    tmp_path,
):
    path = tmp_path / "settings.json"

    service = InterfaceSettingsService(
        path
    )

    service.save_language("en")
    service.save_theme("hacker")

    reloaded = InterfaceSettingsService(
        path
    )

    assert (
        reloaded.load_language()
        == "en"
    )
    assert (
        reloaded.load_theme()
        == "hacker"
    )
