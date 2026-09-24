from __future__ import annotations

import os
import shutil
from dataclasses import asdict, dataclass

import keyring


SERVICE_NAME = "ai-company-os"


@dataclass
class ProviderStatus:
    id: str
    name: str
    configured: bool
    source: str
    description: str

    def to_dict(self) -> dict:
        return asdict(self)


class ProviderService:
    PROVIDERS = {
        "openrouter": {
            "name": "OpenRouter",
            "environment": "OPENROUTER_API_KEY",
        },
        "gemini": {
            "name": "Gemini",
            "environment": "GEMINI_API_KEY",
        },
        "deepseek": {
            "name": "DeepSeek",
            "environment": "DEEPSEEK_API_KEY",
        },
        "grok": {
            "name": "Grok / xAI",
            "environment": "XAI_API_KEY",
        },
    }

    def get_statuses(
        self,
    ) -> list[ProviderStatus]:
        codex = bool(
            shutil.which("codex")
            or shutil.which("codex.cmd")
            or shutil.which("codex.exe")
        )

        ollama = bool(
            shutil.which("ollama")
            or shutil.which("ollama.exe")
        )

        statuses = [
            ProviderStatus(
                id="codex",
                name="Codex",
                configured=codex,
                source=(
                    "Codex CLI"
                    if codex
                    else "Not detected"
                ),
                description=(
                    "Uses the existing Codex / "
                    "ChatGPT authentication flow."
                ),
            ),
            ProviderStatus(
                id="ollama",
                name="Ollama",
                configured=ollama,
                source=(
                    "Local Ollama CLI"
                    if ollama
                    else "Not detected"
                ),
                description=(
                    "Local hardware-aware runtime. "
                    "Model readiness is evaluated "
                    "at execution time."
                ),
            ),
        ]

        for provider_id, config in (
            self.PROVIDERS.items()
        ):
            env_name = config["environment"]

            env_value = os.environ.get(
                env_name
            )

            secure_value = (
                self._get_secure_key(
                    provider_id
                )
            )

            if secure_value:
                source = "Secure credential store"
            elif env_value:
                source = f"Environment: {env_name}"
            else:
                source = "Not configured"

            statuses.append(
                ProviderStatus(
                    id=provider_id,
                    name=config["name"],
                    configured=bool(
                        secure_value
                        or env_value
                    ),
                    source=source,
                    description=(
                        "API key is never stored "
                        "inside the project repository."
                    ),
                )
            )

        return statuses

    def set_api_key(
        self,
        provider: str,
        api_key: str,
    ) -> None:
        provider = (
            provider
            .strip()
            .casefold()
        )

        if provider not in self.PROVIDERS:
            raise ValueError(
                f"Provider does not support API keys: "
                f"{provider}"
            )

        api_key = api_key.strip()

        if not api_key:
            raise ValueError(
                "API key cannot be empty."
            )

        try:
            keyring.set_password(
                SERVICE_NAME,
                provider,
                api_key,
            )
        except Exception as exc:
            raise RuntimeError(
                "Secure credential storage failed."
            ) from exc

    def delete_api_key(
        self,
        provider: str,
    ) -> None:
        provider = (
            provider
            .strip()
            .casefold()
        )

        try:
            keyring.delete_password(
                SERVICE_NAME,
                provider,
            )
        except Exception:
            pass

    def get_api_key(
        self,
        provider: str,
    ) -> str | None:
        provider = (
            provider
            .strip()
            .casefold()
        )

        secure = self._get_secure_key(
            provider
        )

        if secure:
            return secure

        config = self.PROVIDERS.get(
            provider
        )

        if not config:
            return None

        return os.environ.get(
            config["environment"]
        )

    def build_environment(
        self,
        provider: str,
    ) -> dict[str, str]:
        environment = dict(os.environ)

        provider = (
            provider
            .strip()
            .casefold()
        )

        config = self.PROVIDERS.get(
            provider
        )

        if not config:
            return environment

        key = self.get_api_key(
            provider
        )

        if key:
            environment[
                config["environment"]
            ] = key

        return environment

    def build_environment_all(
        self,
    ) -> dict[str, str]:
        environment = dict(os.environ)

        for provider_id, config in (
            self.PROVIDERS.items()
        ):
            key = self.get_api_key(
                provider_id
            )

            if key:
                environment[
                    config["environment"]
                ] = key

        return environment

    def _get_secure_key(
        self,
        provider: str,
    ) -> str | None:
        try:
            return keyring.get_password(
                SERVICE_NAME,
                provider,
            )
        except Exception:
            return None