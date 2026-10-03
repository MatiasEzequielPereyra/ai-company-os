import json
import logging
import shutil
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest

from company_os.application.provider_service import ProviderService, SERVICE_NAME
from company_os.application.provider_capabilities import CAPABILITIES, validate_provider_surfaces
from company_os.application.agent_control_service import AgentControlService
from company_os.application.writable_execution_adapter import WritableExecutionAdapter
from company_os.application.gate_control_service import GateControlService


ROOT = Path(__file__).resolve().parents[1]
FAKE = "obviously-fictional-test-secret"


@pytest.fixture
def credentials(monkeypatch):
    stored = {provider: FAKE + "-" + provider for provider in ProviderService.PROVIDERS}
    monkeypatch.setattr("keyring.get_password", lambda service, provider: stored.get(provider))
    monkeypatch.setattr("keyring.set_password", lambda service, provider, key: stored.update({provider: key}))
    monkeypatch.setattr("keyring.delete_password", lambda service, provider: stored.pop(provider, None))
    for config in ProviderService.PROVIDERS.values():
        monkeypatch.setenv(config["environment"], FAKE + "-ambient")
    return stored


def write_config(root, **config):
    (root / ".codex").mkdir(exist_ok=True)
    (root / ".codex/provider-config.json").write_text(json.dumps(config))


def secret_variables(environment):
    return {name for name in environment if name in {cap.environment for cap in CAPABILITIES.values()}}


def test_catalog_secure_store_and_no_secret_status(credentials, monkeypatch, caplog):
    service = ProviderService()
    monkeypatch.setattr(shutil, "which", lambda _: None)
    assert {status.id for status in service.get_statuses()} == set(CAPABILITIES)
    assert service.PROVIDERS["deepseek"]["environment"] == "DEEPSEEK_API_KEY"
    assert service.PROVIDERS["grok"]["environment"] == "XAI_API_KEY"
    service.set_api_key("DeepSeek", FAKE)
    assert service.get_api_key("deepseek") == FAKE
    service.delete_api_key("deepseek")
    assert "deepseek" not in credentials
    assert FAKE not in repr(service.get_statuses())
    assert FAKE not in repr([s.to_dict() for s in service.get_statuses()])
    assert FAKE not in caplog.text
    for provider in ("ollama", "codex"):
        with pytest.raises(ValueError):
            service.set_api_key(provider, FAKE)
        assert secret_variables(service.build_environment(provider)) == set()


def test_backend_exception_does_not_expose_secret(credentials, monkeypatch):
    def fail(*_):
        raise RuntimeError(FAKE)
    monkeypatch.setattr("keyring.set_password", fail)
    with pytest.raises(RuntimeError) as caught:
        ProviderService().set_api_key("grok", FAKE)
    assert FAKE not in str(caught.value)
    assert caught.value.__suppress_context__


@pytest.mark.parametrize("provider,variable", [("DeepSeek", "DEEPSEEK_API_KEY"), ("Grok", "XAI_API_KEY"), ("OpenRouter", "OPENROUTER_API_KEY"), ("Gemini", "GEMINI_API_KEY")])
def test_explicit_analysis_injects_only_selected_credential(tmp_path, credentials, provider, variable):
    env = ProviderService().build_execution_environment(tmp_path, provider)
    assert secret_variables(env) == {variable}
    assert env[variable] == credentials[provider.casefold()]


def test_auto_role_and_paid_policy(tmp_path, credentials):
    write_config(tmp_path, auto_order=["Ollama"],
                 analysis_auto_order_by_role={"engineering-manager": ["OpenRouter", "Gemini", "DeepSeek", "Grok"]},
                 gate_auto_order=["DeepSeek", "Grok"], allow_paid_fallback=False)
    service = ProviderService()
    assert secret_variables(service.build_execution_environment(tmp_path)) == set()
    assert secret_variables(service.build_execution_environment(tmp_path, roles=("engineering-manager",))) == {"OPENROUTER_API_KEY", "GEMINI_API_KEY"}
    assert secret_variables(service.build_execution_environment(tmp_path, workload="gate")) == set()
    write_config(tmp_path, gate_auto_order=["DeepSeek", "Grok"], allow_paid_fallback=True)
    assert secret_variables(service.build_execution_environment(tmp_path, workload="gate")) == {"DEEPSEEK_API_KEY", "XAI_API_KEY"}


def test_writable_credentials_do_not_grant_capability(tmp_path, credentials):
    service = ProviderService()
    for provider in ("DeepSeek", "Grok"):
        with pytest.raises(ValueError):
            service.build_execution_environment(tmp_path, provider, "writable")
    write_config(tmp_path, writable_auto_order=["Ollama", "DeepSeek", "Grok", "Gemini"], writable_models={"Gemini": "fictional-free-model"})
    (tmp_path / ".codex/writable-policy.json").write_text(json.dumps({"free_provider_models": {"Gemini": ["fictional-free-model"]}}))
    assert secret_variables(service.build_execution_environment(tmp_path, workload="writable")) == {"GEMINI_API_KEY"}
    assert secret_variables(service.build_execution_environment(tmp_path, workload="control")) == set()


@pytest.mark.parametrize("content", ["", "bad-json", "[]"])
def test_unknown_config_discloses_no_secrets(tmp_path, credentials, content):
    write_config(tmp_path)
    (tmp_path / ".codex/provider-config.json").write_text(content)
    assert secret_variables(ProviderService().build_execution_environment(tmp_path)) == set()


def test_ollama_status_requires_resolver_availability(monkeypatch, credentials):
    monkeypatch.setattr("company_os.application.local_runtime_service.LocalRuntimeService.inspect",
                        lambda *_: SimpleNamespace(available=False, profile="LOCAL_CPU_LOW", model="test-model", reason="service unavailable"))
    status = next(s for s in ProviderService(ROOT).get_statuses() if s.id == "ollama")
    assert not status.configured
    assert "service unavailable" in status.description


def runtime_validate_set(script, *, environment_symbols=False):
    # PowerShell AST is a real language symbol; no documentation/source regex.
    executable = shutil.which("pwsh") or shutil.which("powershell")
    assert executable, "PowerShell is required for the cross-layer contract test"
    command = "$ast=[System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$null,[ref]$null); $p=$ast.ParamBlock.Parameters | Where-Object {$_.Name.VariablePath.UserPath -eq 'Provider'}; @($p.Attributes | Where-Object {$_.TypeName.Name -eq 'ValidateSet'} | ForEach-Object {$_.PositionalArguments.Value}) | ConvertTo-Json -Compress"
    if environment_symbols:
        command = "$ast=[System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$null,[ref]$null); @($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.IsDriveQualified -and $n.VariablePath.DriveName -eq 'env'},$true) | ForEach-Object {$_.VariablePath.UserPath.Substring(4)} | Sort-Object -Unique) | ConvertTo-Json -Compress"
    # -Command does not accept a trailing argument portably; pass path through env.
    env = ProviderService._clean_environment()
    env["AICO_CONTRACT_SCRIPT"] = str(script)
    command = command.replace("$args[0]", "$env:AICO_CONTRACT_SCRIPT")
    process = subprocess.run([executable, "-NoProfile", "-Command", command], env=env, capture_output=True, text=True, timeout=30, check=True)
    return json.loads(process.stdout)


def test_cross_layer_capability_contract():
    from company_os.cli.tui import ProvidersScreen
    runtime = runtime_validate_set(ROOT / "scripts/provider-router.ps1")
    mapping = {p: c["environment"] for p, c in ProviderService.PROVIDERS.items()}
    validate_provider_surfaces(runtime, mapping, {s.id for s in ProviderService().get_statuses()}, ProvidersScreen.CREDENTIAL_PROVIDERS)
    writable = {p.casefold() for p in runtime_validate_set(ROOT / "scripts/run-writable-agent.ps1")} - {"auto"}
    assert writable == {p for p, cap in CAPABILITIES.items() if cap.writable}
    for provider in runtime:
        if provider == "Auto":
            continue
        adapter = "xai" if provider == "Grok" else provider.lower()
        assert (ROOT / f"scripts/providers/invoke-{adapter}.ps1").is_file()
        if CAPABILITIES[provider.lower()].environment:
            symbols = runtime_validate_set(ROOT / f"scripts/providers/invoke-{adapter}.ps1", environment_symbols=True)
            assert CAPABILITIES[provider.lower()].environment in symbols


@pytest.mark.parametrize("missing_surface", ["visible", "mapping", "tui"])
def test_contract_detector_rejects_missing_runtime_provider(missing_surface):
    runtime = ["Auto", *CAPABILITIES]
    visible = set(CAPABILITIES)
    mapping = {p: cap.environment for p, cap in CAPABILITIES.items() if cap.environment}
    configurable = set(mapping)
    if missing_surface == "visible":
        visible.remove("deepseek")
    elif missing_surface == "mapping":
        mapping.pop("deepseek")
    else:
        configurable.remove("deepseek")
    with pytest.raises(ValueError):
        validate_provider_surfaces(runtime, mapping, visible, configurable)


def test_agent_control_injects_explicit_deepseek_only(tmp_path, monkeypatch, credentials):
    script = tmp_path / "scripts/run-active-agents.ps1"
    script.parent.mkdir()
    script.write_text("# mocked runner")
    service = AgentControlService()
    monkeypatch.setattr(service, "get_tasks", lambda *_: [])
    monkeypatch.setattr(service, "_powershell", lambda: "mock-powershell")
    captured = {}
    def run(*args, **kwargs):
        captured.update(kwargs["env"])
        return SimpleNamespace(returncode=0, output="mock output")
    monkeypatch.setattr("company_os.application.agent_control_service.run_streamed_process", run)
    service._run_script(script, ["-Provider", "DeepSeek"], 1)
    assert secret_variables(captured) == {"DEEPSEEK_API_KEY"}


def test_gate_control_injects_explicit_grok_only(tmp_path, monkeypatch, credentials):
    script = tmp_path / "scripts/run-gate-agent.ps1"
    script.parent.mkdir()
    script.write_text("# mocked runner")
    service = GateControlService()
    monkeypatch.setattr(service, "_powershell", lambda: "mock-powershell")
    captured = {}
    def run(*args, **kwargs):
        captured.update(kwargs["env"])
        return SimpleNamespace(returncode=0, output="mock output")
    monkeypatch.setattr("company_os.application.gate_control_service.run_streamed_process", run)
    service._run_script(script, ["-Provider", "Grok"], 1)
    assert secret_variables(captured) == {"XAI_API_KEY"}


def test_writable_adapter_injects_only_explicit_gemini(tmp_path, monkeypatch, credentials):
    script = tmp_path / "scripts/run-writable-agent.ps1"
    script.parent.mkdir()
    script.write_text("# mocked runner")
    service = WritableExecutionAdapter()
    monkeypatch.setattr(service.control, "get_tasks", lambda *_: [SimpleNamespace(status="READY", work_kind="IMPLEMENTATION")])
    monkeypatch.setattr(service, "_powershell", lambda: "mock-powershell")
    captured = {}
    def run(*args, **kwargs):
        captured.update(kwargs["env"])
        return SimpleNamespace(returncode=1, output="fixture stop before result handling")
    monkeypatch.setattr("company_os.application.writable_execution_adapter.run_streamed_process", run)
    with pytest.raises(RuntimeError, match="fixture stop"):
        service.run(tmp_path, "AICO-FAKE", tmp_path, "Gemini")
    assert secret_variables(captured) == {"GEMINI_API_KEY"}


def test_writable_auto_does_not_inject_unlisted_cloud_model(tmp_path, credentials):
    write_config(tmp_path, writable_auto_order=["Gemini"], writable_models={"Gemini": "fictional-paid-model"})
    (tmp_path / ".codex/writable-policy.json").write_text(json.dumps({"free_provider_models": {"Gemini": ["fictional-free-model"]}}))
    assert secret_variables(ProviderService().build_execution_environment(tmp_path, workload="writable")) == set()
