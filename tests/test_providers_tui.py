from __future__ import annotations

import asyncio
import threading
from io import StringIO

import pytest
from rich.console import Console
from textual.app import App
from textual.widgets import Button, Input, Static

from company_os.application.provider_service import ProviderService, ProviderStatus
from company_os.cli.tui import ProvidersScreen


class ProviderHarness(App):
    language = "en"
    project = None

    def on_mount(self):
        self.push_screen(ProvidersScreen())


@pytest.fixture
def credential_store(monkeypatch):
    store = {}
    monkeypatch.setattr("company_os.application.provider_service.keyring.set_password",
                        lambda _service, provider, key: store.__setitem__(provider, key))
    monkeypatch.setattr("company_os.application.provider_service.keyring.get_password",
                        lambda _service, provider: store.get(provider))
    monkeypatch.setattr("company_os.application.provider_service.keyring.delete_password",
                        lambda _service, provider: store.pop(provider, None))

    def statuses(_self):
        return [
            ProviderStatus("codex", "Codex", True, "Codex CLI", "CLI presence only"),
            ProviderStatus("ollama", "Ollama", False, "Local runtime", "Service unavailable"),
            *[ProviderStatus(provider, config["name"], provider in store,
                             "Secure credential store" if provider in store else "Not configured",
                             "API key provider")
              for provider, config in ProviderService.PROVIDERS.items()],
        ]

    monkeypatch.setattr(ProviderService, "get_statuses", statuses)
    return store


def render_status(screen):
    output = StringIO()
    Console(file=output, width=160).print(screen.query_one("#providers-content", Static).content)
    return output.getvalue()


@pytest.mark.parametrize("provider", ["openrouter", "gemini", "deepseek", "grok"])
def test_provider_widgets_save_update_delete_and_navigation(provider, credential_store):
    async def scenario():
        app = ProviderHarness()
        async with app.run_test(size=(160, 60)) as pilot:
            await app.workers.wait_for_complete()
            screen = app.screen
            assert isinstance(screen, ProvidersScreen)
            inputs = list(screen.query(Input))
            assert {widget.id for widget in inputs} == {
                f"{name}-key" for name in ProvidersScreen.CREDENTIAL_PROVIDERS
            } == {"openrouter-key", "gemini-key", "deepseek-key", "grok-key"}
            assert all(widget.password and widget.value == "" for widget in inputs)
            assert len(list(screen.query(Button))) == 4
            assert "Codex CLI" in render_status(screen)
            assert "Service unavailable" in render_status(screen)

            field = screen.query_one(f"#{provider}-key", Input)
            for secret in ("FICTIONAL-TUI-KEY-ONE", "FICTIONAL-TUI-KEY-TWO"):
                field.focus()
                await pilot.press(*list(secret))
                await pilot.press("enter")
                await pilot.pause()
                await app.workers.wait_for_complete()
                assert credential_store[provider] == secret
                assert field.value == ""
                assert secret not in render_status(screen)
                assert secret not in app.export_screenshot()

            await pilot.click(f"#{provider}-delete-key")
            await pilot.pause()
            await app.workers.wait_for_complete()
            assert provider not in credential_store
            assert field.value == ""
            await pilot.press("escape")
            await pilot.pause()
            assert not isinstance(app.screen, ProvidersScreen)

    asyncio.run(scenario())


@pytest.mark.parametrize("operation", ["save", "delete"])
def test_provider_failure_notifications_do_not_expose_submitted_secret(operation, monkeypatch, credential_store):
    secret = "FICTIONAL-EXCEPTION-TUI-KEY"

    def failing_set(*_args):
        raise RuntimeError(secret)

    monkeypatch.setattr(ProviderService, "set_api_key" if operation == "save" else "delete_api_key", failing_set)
    notifications = []
    monkeypatch.setattr(ProvidersScreen, "notify",
                        lambda _self, message, **_kwargs: notifications.append(message))

    async def scenario():
        app = ProviderHarness()
        async with app.run_test(size=(160, 60)) as pilot:
            await app.workers.wait_for_complete()
            field = app.screen.query_one("#deepseek-key", Input)
            field.focus()
            await pilot.press(*list(secret))
            if operation == "save":
                await pilot.press("enter")
            else:
                await pilot.click("#deepseek-delete-key")
            await pilot.pause()
            assert field.value == ""
            assert notifications == ["Could not update the secure credential store."]
            assert secret not in app.export_screenshot()

    asyncio.run(scenario())


def test_provider_status_worker_does_not_block_navigation(monkeypatch):
    started = threading.Event()
    release = threading.Event()

    def slow_statuses(_self):
        started.set()
        release.wait(timeout=5)
        return []

    monkeypatch.setattr(ProviderService, "get_statuses", slow_statuses)

    async def scenario():
        app = ProviderHarness()
        async with app.run_test(size=(100, 30)) as pilot:
            try:
                await pilot.pause()
                assert started.is_set()
                assert not release.is_set()
                await pilot.press("escape")
                assert not isinstance(app.screen, ProvidersScreen)
            finally:
                release.set()

    asyncio.run(scenario())


def test_provider_screen_tracks_interface_language(credential_store):
    async def scenario():
        app = ProviderHarness()
        async with app.run_test(size=(160, 60)) as pilot:
            await app.workers.wait_for_complete()
            app.language = "es"
            screen = app.screen
            screen.refresh_language()
            await app.workers.wait_for_complete()
            await pilot.pause()
            assert "Enter para guardar" in screen.query_one("#deepseek-key", Input).placeholder
            assert "Eliminar" in str(screen.query_one("#grok-delete-key", Button).label)
            assert "Proveedores" in render_status(screen)

    asyncio.run(scenario())
