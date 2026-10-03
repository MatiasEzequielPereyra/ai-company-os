from __future__ import annotations

import copy
import json
import subprocess
from types import SimpleNamespace

import pytest

from company_os.application.local_runtime_service import LocalRuntimeService
from company_os.application.provider_capabilities import CAPABILITIES


@pytest.fixture
def resolver_payload():
    return {
        "Available": True, "Profile": "LOCAL_GPU_8GB", "CapabilityScore": 72,
        "Model": "fixture-coder:7b", "Reason": "Best installed role-preferred model.",
        "NumCtx": 8192, "NumPredict": 2048,
        "Hardware": {"capability_score": 72, "memory": {"total_gb": 32.0},
                     "gpu": {"name": "Fixture GPU", "vram_gb": 8.0},
                     "ollama": {"reachable": True}},
    }


@pytest.fixture
def resolver(tmp_path, monkeypatch):
    script = tmp_path / "scripts/local-runtime/resolve-local-runtime.ps1"
    script.parent.mkdir(parents=True)
    script.write_text("# deterministic fixture", encoding="utf-8")
    monkeypatch.setattr("company_os.application.local_runtime_service.shutil.which", lambda _: "fixture-pwsh")
    service = LocalRuntimeService(cache_seconds=0)
    return tmp_path, service


def response(monkeypatch, payload, *, returncode=0):
    monkeypatch.setattr("company_os.application.local_runtime_service.subprocess.run", lambda *_a, **_kw:
                        SimpleNamespace(returncode=returncode, stdout=payload, stderr="fixture-secret-error"))


def test_resolver_authoritative_values_and_workload(resolver, resolver_payload, monkeypatch):
    root, service = resolver
    calls = []
    def run(command, **kwargs):
        calls.append((command, kwargs))
        return SimpleNamespace(returncode=0, stdout=json.dumps(resolver_payload))
    monkeypatch.setattr("company_os.application.local_runtime_service.subprocess.run", run)
    status = service.inspect(root, role="backend", workload="writable")
    assert status.available and status.model == "fixture-coder:7b"
    assert (status.ram_gb, status.vram_gb, status.num_ctx, status.num_predict) == (32.0, 8.0, 8192, 2048)
    assert "-Role 'backend' -Workload 'writable'" in calls[0][0][-1]
    assert calls[0][1]["timeout"] == 20


def test_metadata_probe_receives_no_provider_credentials(resolver, resolver_payload, monkeypatch):
    root, service = resolver
    secret_names = {entry.environment for entry in CAPABILITIES.values() if entry.environment} | {"CODEX_API_KEY"}
    for name in secret_names:
        monkeypatch.setenv(name, "OBVIOUSLY_FAKE_RUNTIME_METADATA_SECRET")
    monkeypatch.setenv("OLLAMA_HOST", "http://fixture-localhost:11434")
    captured = []
    def run(*_args, **kwargs):
        captured.append(set(kwargs["env"]))
        assert kwargs["env"]["OLLAMA_HOST"] == "http://fixture-localhost:11434"
        return SimpleNamespace(returncode=0, stdout=json.dumps(resolver_payload))
    monkeypatch.setattr("company_os.application.local_runtime_service.subprocess.run", run)
    assert service.inspect(root).available
    assert not (captured[0] & secret_names)


def test_legitimate_unavailable_without_top_level_score(resolver, resolver_payload, monkeypatch):
    root, service = resolver
    resolver_payload.update(Available=False, Model="", Reason="Ollama is not reachable.")
    resolver_payload["Hardware"]["ollama"]["reachable"] = False
    del resolver_payload["CapabilityScore"]
    response(monkeypatch, json.dumps(resolver_payload))
    status = service.inspect(root)
    assert not status.available
    assert status.reason == "Ollama is not reachable."
    assert status.capability_score == 72


@pytest.mark.parametrize("output", ["", "garbage", "{}", "null", "[]", '{"Available": true}',
                                        '{"Available": "false"}', '{}\n{}'])
def test_invalid_responses_fail_closed(resolver, monkeypatch, output):
    root, service = resolver
    response(monkeypatch, output)
    status = service.inspect(root)
    assert not status.available and status.profile == "" and status.model == ""
    assert status.ram_gb is None and status.num_ctx is None


@pytest.mark.parametrize("field,value", [("Available", "true"), ("NumCtx", 0), ("NumPredict", "2048"),
                                         ("CapabilityScore", 101), ("Hardware", []), ("Model", "")])
def test_invalid_required_fields(resolver, resolver_payload, monkeypatch, field, value):
    root, service = resolver
    resolver_payload[field] = value
    response(monkeypatch, json.dumps(resolver_payload))
    assert not service.inspect(root).available


@pytest.mark.parametrize("field", ["Available", "Profile", "Model", "Reason", "NumCtx", "NumPredict", "Hardware"])
def test_missing_required_fields(resolver, resolver_payload, monkeypatch, field):
    root, service = resolver
    del resolver_payload[field]
    response(monkeypatch, json.dumps(resolver_payload))
    assert not service.inspect(root).available


def test_contradictory_reachability_and_nonfinite_hardware(resolver, resolver_payload, monkeypatch):
    root, service = resolver
    unreachable = copy.deepcopy(resolver_payload)
    unreachable["Hardware"]["ollama"]["reachable"] = False
    response(monkeypatch, json.dumps(unreachable))
    assert not service.inspect(root).available
    resolver_payload["Hardware"]["memory"]["total_gb"] = float("nan")
    response(monkeypatch, json.dumps(resolver_payload))
    assert service.inspect(root).ram_gb is None


def test_process_failure_does_not_surface_raw_output(resolver, monkeypatch):
    root, service = resolver
    response(monkeypatch, "fixture-secret-output", returncode=1)
    status = service.inspect(root)
    assert not status.available and "fixture-secret" not in repr(status)


@pytest.mark.parametrize("error", [OSError("fixture-secret"), subprocess.TimeoutExpired("fixture-secret", 20)])
def test_start_failure_and_timeout(resolver, monkeypatch, error):
    root, service = resolver
    def fail(*_args, **_kwargs):
        raise error
    monkeypatch.setattr("company_os.application.local_runtime_service.subprocess.run", fail)
    status = service.inspect(root)
    assert not status.available and status.num_ctx is None
    assert "fixture-secret" not in repr(status)


def test_missing_resolver_and_powershell(resolver, monkeypatch, tmp_path):
    root, service = resolver
    assert not service.inspect(root / "absent").available
    monkeypatch.setattr("company_os.application.local_runtime_service.shutil.which", lambda _: None)
    assert not service.inspect(root).available


def test_cache_distinguishes_role_workload_and_invalidates(resolver, resolver_payload, monkeypatch):
    root, service = resolver
    service.cache_seconds = 30
    calls = []
    def run(*_args, **_kwargs):
        calls.append(True)
        return SimpleNamespace(returncode=0, stdout=json.dumps(resolver_payload))
    monkeypatch.setattr("company_os.application.local_runtime_service.subprocess.run", run)
    service.inspect(root, "backend", "analysis")
    service.inspect(root, "backend", "analysis")
    service.inspect(root, "backend", "writable")
    service.inspect(root, "frontend", "analysis")
    assert len(calls) == 3
    service.invalidate(root)
    service.inspect(root, "backend", "analysis")
    assert len(calls) == 4
