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
    service = LocalRuntimeService()

    status = service.inspect(
        tmp_path,
    )

    assert status.available is False
    assert (
        "resolver is not installed"
        in status.reason
    )
