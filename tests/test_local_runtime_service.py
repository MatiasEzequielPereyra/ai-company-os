from __future__ import annotations

import json
from pathlib import Path

from company_os.application.local_runtime_service import (
    LocalRuntimeService,
)


def test_local_runtime_service_parses_and_caches_status(
    tmp_path: Path,
    monkeypatch,
) -> None:
    LocalRuntimeService._shared_cache.clear()
    LocalRuntimeService._force_refresh_projects.clear()

    root = tmp_path / "project"
    script = (
        root
        / "scripts"
        / "local-runtime"
        / "resolve-local-runtime.ps1"
    )
    script.parent.mkdir(
        parents=True
    )
    script.write_text(
        "# fixture",
        encoding="utf-8",
    )

    monkeypatch.setattr(
        LocalRuntimeService,
        "_powershell",
        staticmethod(
            lambda: "powershell.exe"
        ),
    )

    calls = []

    payload = {
        "Available": True,
        "Profile": "LOCAL_GPU_12GB",
        "CapabilityScore": 82,
        "Model": "qwen2.5-coder:14b",
        "Reason": "fixture",
        "NumCtx": 16384,
        "NumPredict": 2048,
        "Hardware": {
            "memory": {
                "total_gb": 32.0,
            },
            "gpu": {
                "name": "RTX fixture",
                "vram_gb": 12.0,
            },
        },
    }

    class Result:
        returncode = 0
        stdout = (
            json.dumps(payload)
            + "\n"
        )
        stderr = ""

    def fake_run(*args, **kwargs):
        calls.append(
            (args, kwargs)
        )
        return Result()

    monkeypatch.setattr(
        "company_os.application."
        "local_runtime_service."
        "subprocess.run",
        fake_run,
    )

    service = LocalRuntimeService(
        cache_seconds=60,
    )

    first = service.inspect(
        root,
        role="backend",
        workload="analysis",
    )
    second = service.inspect(
        root,
        role="backend",
        workload="analysis",
    )

    assert first == second
    assert first.available is True
    assert first.profile == "LOCAL_GPU_12GB"
    assert first.capability_score == 82
    assert first.model == "qwen2.5-coder:14b"
    assert first.ram_gb == 32.0
    assert first.vram_gb == 12.0
    assert first.num_ctx == 16384
    assert first.num_predict == 2048
    assert len(calls) == 1


def test_local_runtime_service_handles_missing_resolver(
    tmp_path: Path,
) -> None:
    LocalRuntimeService._shared_cache.clear()
    LocalRuntimeService._force_refresh_projects.clear()

    service = LocalRuntimeService()

    status = service.inspect(
        tmp_path,
    )

    assert status.available is False
    assert (
        "Local runtime is not installed"
        in status.reason
    )
    assert "update-runtime.ps1" in status.reason


def test_local_runtime_service_uses_snapshot_fast_path(
    tmp_path: Path,
    monkeypatch,
) -> None:
    LocalRuntimeService._shared_cache.clear()
    LocalRuntimeService._force_refresh_projects.clear()

    root = tmp_path / "project"
    script = (
        root
        / "scripts"
        / "local-runtime"
        / "resolve-local-runtime.ps1"
    )
    script.parent.mkdir(
        parents=True
    )
    script.write_text(
        "# fixture",
        encoding="utf-8",
    )

    capability = (
        root
        / ".codex"
        / "runtime"
        / "local-capability.json"
    )
    capability.parent.mkdir(
        parents=True
    )
    capability.write_text(
        json.dumps(
            {
                "profile": "LOCAL_CPU_LOW"
            }
        ),
        encoding="utf-8",
    )

    monkeypatch.setattr(
        LocalRuntimeService,
        "_powershell",
        staticmethod(
            lambda: "powershell.exe"
        ),
    )

    commands = []

    payload = {
        "Available": True,
        "Profile": "LOCAL_CPU_LOW",
        "CapabilityScore": 44,
        "Model": "llama3.1:8b",
        "Reason": "snapshot",
        "NumCtx": 8192,
        "NumPredict": 1024,
        "Hardware": {
            "profile": "LOCAL_CPU_LOW",
            "capability_score": 44,
            "memory": {
                "total_gb": 15.72,
            },
            "gpu": {
                "name": "Intel UHD",
                "vram_gb": 1.0,
            },
        },
    }

    class Result:
        returncode = 0
        stdout = json.dumps(payload) + "\n"
        stderr = ""

    def fake_run(args, **kwargs):
        commands.append(
            args[-1]
        )
        return Result()

    monkeypatch.setattr(
        "company_os.application."
        "local_runtime_service."
        "subprocess.run",
        fake_run,
    )

    service = LocalRuntimeService()
    service.inspect(
        root,
        role="pm",
    )

    assert len(commands) == 1
    assert "-HardwareSnapshotPath" in commands[0]


def test_local_runtime_service_f5_forces_fresh_probe(
    tmp_path: Path,
    monkeypatch,
) -> None:
    LocalRuntimeService._shared_cache.clear()
    LocalRuntimeService._force_refresh_projects.clear()

    root = tmp_path / "project"
    script = (
        root
        / "scripts"
        / "local-runtime"
        / "resolve-local-runtime.ps1"
    )
    script.parent.mkdir(
        parents=True
    )
    script.write_text(
        "# fixture",
        encoding="utf-8",
    )

    capability = (
        root
        / ".codex"
        / "runtime"
        / "local-capability.json"
    )
    capability.parent.mkdir(
        parents=True
    )
    capability.write_text(
        "{}",
        encoding="utf-8",
    )

    monkeypatch.setattr(
        LocalRuntimeService,
        "_powershell",
        staticmethod(
            lambda: "powershell.exe"
        ),
    )

    commands = []

    payload = {
        "Available": True,
        "Profile": "LOCAL_CPU_LOW",
        "CapabilityScore": 44,
        "Model": "llama3.1:8b",
        "Reason": "fresh",
        "NumCtx": 8192,
        "NumPredict": 1024,
        "Hardware": {
            "profile": "LOCAL_CPU_LOW",
            "capability_score": 44,
            "memory": {
                "total_gb": 15.72,
            },
            "gpu": {
                "name": "Intel UHD",
                "vram_gb": 1.0,
            },
        },
    }

    class Result:
        returncode = 0
        stdout = json.dumps(payload) + "\n"
        stderr = ""

    def fake_run(args, **kwargs):
        commands.append(
            args[-1]
        )
        return Result()

    monkeypatch.setattr(
        "company_os.application."
        "local_runtime_service."
        "subprocess.run",
        fake_run,
    )

    service = LocalRuntimeService()
    service.invalidate(root)
    service.inspect(
        root,
        role="pm",
    )

    assert len(commands) == 1
    assert "-HardwareSnapshotPath" not in commands[0]
