from __future__ import annotations

import os
import shutil
import json
from pathlib import Path
from dataclasses import asdict, dataclass

import keyring
from company_os.application.provider_capabilities import CAPABILITIES


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
    def __init__(self, project_root: str | Path | None = None) -> None:
        self.project_root = Path(project_root) if project_root else None
    PROVIDERS = {
        provider: {"name": capability.name, "environment": capability.environment}
        for provider, capability in CAPABILITIES.items()
        if capability.environment
    }

    def get_statuses(
        self,
    ) -> list[ProviderStatus]:
        codex = bool(
            shutil.which("codex")
            or shutil.which("codex.cmd")
            or shutil.which("codex.exe")
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
            )
        ]

        from company_os.application.local_runtime_service import LocalRuntimeService

        local = LocalRuntimeService().inspect(self.project_root) if self.project_root else None
        statuses.append(ProviderStatus(
            id="ollama", name="Ollama", configured=bool(local and local.available),
            source="Local runtime" if local and local.available else "Not verified / unavailable",
            description=(f"{local.profile}; {local.model}; {local.reason}" if local
                         else "Select a project to verify service, hardware and selected model. No API key required."),
        ))

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
            ) from None

    def delete_api_key(
        self,
        provider: str,
    ) -> None:
        provider = (
            provider
            .strip()
            .casefold()
        )

        if provider not in self.PROVIDERS:
            raise ValueError("Provider does not support API keys")
        try:
            keyring.delete_password(
                SERVICE_NAME,
                provider,
            )
        except keyring.errors.PasswordDeleteError:
            pass
        except Exception:
            raise RuntimeError("Secure credential deletion failed.") from None

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
        environment = self._clean_environment()

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

    @staticmethod
    def _clean_environment() -> dict[str, str]:
        environment = dict(os.environ)
        for capability in CAPABILITIES.values():
            if capability.environment:
                environment.pop(capability.environment, None)
        # Codex uses its CLI authentication, not an injected provider key.
        environment.pop("CODEX_API_KEY", None)
        return environment

    def build_execution_environment(
        self, project_root: str | Path, provider: str = "Auto",
        workload: str = "analysis", roles: tuple[str, ...] = (),
    ) -> dict[str, str]:
        """Inject only credentials for the runtime's possible candidates.

        This filters secret exposure; PowerShell still selects and validates
        providers, models, local profiles and writable policy.
        """
        environment = self._clean_environment()
        if workload not in {"general", "analysis", "gate", "writable"}:
            return environment
        requested = provider.strip().casefold()
        if requested != "auto":
            capability = CAPABILITIES.get(requested)
            if capability is None or not getattr(capability, workload, True):
                raise ValueError("Provider is not supported for this workload")
            candidates = {requested}
        else:
            config_path = Path(project_root) / ".codex" / "provider-config.json"
            try:
                config = json.loads(config_path.read_text(encoding="utf-8-sig"))
                if not isinstance(config, dict):
                    raise ValueError("Invalid provider configuration")
            except (OSError, ValueError):
                # Unknown routing must not disclose stored credentials.
                return environment
            order_key = {"general": "auto_order", "analysis": "auto_order",
                         "gate": "gate_auto_order", "writable": "writable_auto_order"}[workload]
            default_order = ["Ollama"] if workload == "writable" else config.get("auto_order")
            order = config.get(order_key) or default_order or ["Ollama"]
            if not isinstance(order, list):
                return environment
            if workload == "analysis" and roles:
                overrides = config.get("analysis_auto_order_by_role", {})
                if not isinstance(overrides, dict) or any(
                    not isinstance(overrides.get(role, order), list) for role in roles
                ):
                    return environment
                order = [candidate for role in roles
                         for candidate in (overrides.get(role) or order)]
            candidates = {name.casefold() for name in order if isinstance(name, str)}
            if workload == "writable":
                try:
                    policy = json.loads((Path(project_root) / ".codex/writable-policy.json").read_text(encoding="utf-8-sig"))
                    allowlist = policy["free_provider_models"]
                    models = config.get("writable_models", {})
                    defaults = config.get("models", {})
                    candidates = {candidate for candidate in candidates
                                  if candidate == "ollama" or (
                                      (name := CAPABILITIES[candidate].name) in allowlist
                                      and (models.get(name) or defaults.get(name)) in allowlist[name]
                                  )}
                except (OSError, ValueError, KeyError, TypeError, AttributeError):
                    return environment
            if workload != "writable" and config.get("allow_paid_fallback") is not True:
                candidates -= {"deepseek", "grok"}
        for candidate in candidates:
            capability = CAPABILITIES.get(candidate)
            if capability and getattr(capability, workload, True) and capability.environment:
                key = self.get_api_key(candidate)
                if key:
                    environment[capability.environment] = key
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
