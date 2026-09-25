from __future__ import annotations

from company_os.application.provider_service import (
    ProviderService,
)


def test_provider_catalog_includes_new_cloud_providers() -> None:
    assert (
        ProviderService.PROVIDERS[
            "deepseek"
        ]["environment"]
        == "DEEPSEEK_API_KEY"
    )
    assert (
        ProviderService.PROVIDERS[
            "grok"
        ]["environment"]
        == "XAI_API_KEY"
    )


def test_build_environment_all_injects_configured_keys(
    monkeypatch,
) -> None:
    service = ProviderService()

    keys = {
        "openrouter": "or-key",
        "gemini": "gem-key",
        "deepseek": "ds-key",
        "grok": "xai-key",
    }

    monkeypatch.setattr(
        service,
        "get_api_key",
        lambda provider: keys.get(
            provider
        ),
    )

    environment = (
        service.build_environment_all()
    )

    assert (
        environment[
            "OPENROUTER_API_KEY"
        ]
        == "or-key"
    )
    assert (
        environment[
            "GEMINI_API_KEY"
        ]
        == "gem-key"
    )
    assert (
        environment[
            "DEEPSEEK_API_KEY"
        ]
        == "ds-key"
    )
    assert (
        environment[
            "XAI_API_KEY"
        ]
        == "xai-key"
    )
