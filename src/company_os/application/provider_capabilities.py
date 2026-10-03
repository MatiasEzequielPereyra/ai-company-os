"""Application view of runtime capabilities; routing remains PowerShell-owned."""
from dataclasses import dataclass


@dataclass(frozen=True)
class ProviderCapability:
    name: str
    analysis: bool = True
    gate: bool = True
    writable: bool = False
    environment: str | None = None
    local: bool = False
    cli: bool = False


CAPABILITIES = {
    "codex": ProviderCapability("Codex", cli=True),
    "ollama": ProviderCapability("Ollama", writable=True, local=True),
    "openrouter": ProviderCapability("OpenRouter", writable=True, environment="OPENROUTER_API_KEY"),
    "gemini": ProviderCapability("Gemini", writable=True, environment="GEMINI_API_KEY"),
    "deepseek": ProviderCapability("DeepSeek", environment="DEEPSEEK_API_KEY"),
    "grok": ProviderCapability("Grok / xAI", environment="XAI_API_KEY"),
}


def validate_provider_surfaces(runtime_providers, credential_mapping, visible, configurable):
    """Reject missing capabilities without equating legitimate workload subsets."""
    runtime_ids = {name.casefold() for name in runtime_providers} - {"auto"}
    if runtime_ids != set(CAPABILITIES):
        raise ValueError("Runtime capability catalog differs from application contract")
    if not runtime_ids <= set(visible):
        raise ValueError("Runtime provider missing from ProviderService")
    for provider, capability in CAPABILITIES.items():
        if capability.environment:
            if credential_mapping.get(provider) != capability.environment:
                raise ValueError("Credential mapping missing or incorrect")
            if provider not in configurable:
                raise ValueError("Credential provider missing from TUI")
