from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

from company_os.application.provider_capabilities import CAPABILITIES


@dataclass(frozen=True)
class LocalRuntimeStatus:
    available: bool = False
    profile: str = ""
    capability_score: int | None = None
    model: str = ""
    reason: str = ""
    ram_gb: float | None = None
    gpu_name: str = ""
    vram_gb: float | None = None
    num_ctx: int | None = None
    num_predict: int | None = None


class LocalRuntimeService:
    """Expose the PowerShell resolver's decision without reproducing its policy."""

    def __init__(self, cache_seconds: float = 30, timeout_seconds: float = 20) -> None:
        self.cache_seconds = cache_seconds
        self.timeout_seconds = timeout_seconds
        self._cache: dict[tuple[str, str, str], tuple[float, LocalRuntimeStatus]] = {}
        self._generation = 0

    def inspect(
        self, project_root: str | Path, role: str = "pm", workload: str = "analysis",
    ) -> LocalRuntimeStatus:
        root = Path(project_root).resolve()
        key = (str(root), role.strip().casefold(), workload.strip().casefold())
        cached = self._cache.get(key)
        if cached and time.monotonic() - cached[0] < self.cache_seconds:
            return cached[1]
        generation = self._generation
        status = self._inspect_uncached(root, key[1], key[2])
        if generation == self._generation:
            self._cache[key] = (time.monotonic(), status)
        return status

    def invalidate(self, project_root: str | Path | None = None) -> None:
        self._generation += 1
        if project_root is None:
            self._cache.clear()
        else:
            root = str(Path(project_root).resolve())
            self._cache = {key: value for key, value in self._cache.items() if key[0] != root}

    @staticmethod
    def _ps_literal(value: str) -> str:
        return "'" + value.replace("'", "''") + "'"

    def _inspect_uncached(self, root: Path, role: str, workload: str) -> LocalRuntimeStatus:
        script = root / "scripts" / "local-runtime" / "resolve-local-runtime.ps1"
        if not script.is_file():
            return LocalRuntimeStatus(reason="Local runtime resolver is not installed.")
        powershell = next((path for name in ("pwsh", "powershell.exe", "powershell")
                           if (path := shutil.which(name))), None)
        if not powershell:
            return LocalRuntimeStatus(reason="PowerShell runtime was not found.")
        command = (
            "$ErrorActionPreference = 'Stop'; $WarningPreference = 'SilentlyContinue'; "
            "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); "
            "$result = & " + self._ps_literal(str(script))
            + " -ProjectPath " + self._ps_literal(str(root))
            + " -Role " + self._ps_literal(role)
            + " -Workload " + self._ps_literal(workload)
            + "; $result | ConvertTo-Json -Depth 20 -Compress"
        )
        try:
            environment = dict(os.environ)
            for capability in CAPABILITIES.values():
                if capability.environment:
                    environment.pop(capability.environment, None)
            environment.pop("CODEX_API_KEY", None)
            process = subprocess.run(
                [powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-Command", command], capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=self.timeout_seconds,
                env=environment,
            )
        except subprocess.TimeoutExpired:
            return LocalRuntimeStatus(reason="Local runtime inspection timed out.")
        except OSError:
            return LocalRuntimeStatus(reason="Local runtime inspection could not start.")
        if process.returncode:
            # Raw subprocess output may contain environment details; never surface it.
            return LocalRuntimeStatus(reason="Local runtime resolver failed.")
        try:
            return self._parse(json.loads((process.stdout or "").lstrip("\ufeff")))
        except (ValueError, TypeError, KeyError, OverflowError):
            return LocalRuntimeStatus(reason="Local runtime returned an invalid status.")

    @staticmethod
    def _parse(payload: object) -> LocalRuntimeStatus:
        if not isinstance(payload, dict):
            raise ValueError("Expected status object")
        available = payload["Available"]
        if type(available) is not bool:
            raise ValueError("Expected boolean availability")
        def string(source: dict, key: str, *, nonempty: bool = False) -> str:
            value = source[key]
            if not isinstance(value, str) or (nonempty and not value.strip()):
                raise ValueError(key)
            return value
        def number(source: dict, key: str, *, integer: bool = False, positive: bool = False):
            value = source[key]
            if type(value) not in ((int,) if integer else (int, float)):
                raise ValueError(key)
            if not math.isfinite(value) or value < 0 or (positive and value == 0):
                raise ValueError(key)
            return value
        hardware = payload["Hardware"]
        if not isinstance(hardware, dict):
            raise ValueError("Hardware")
        memory, gpu = hardware["memory"], hardware["gpu"]
        if not isinstance(memory, dict) or not isinstance(gpu, dict):
            raise ValueError("Hardware shape")
        # Some legitimate unavailable branches omit CapabilityScore at top level.
        score_source = payload if "CapabilityScore" in payload else hardware
        score_key = "CapabilityScore" if score_source is payload else "capability_score"
        score = number(score_source, score_key, integer=True)
        if score > 100:
            raise ValueError("Capability score")
        if available:
            ollama = hardware["ollama"]
            if not isinstance(ollama, dict) or ollama.get("reachable") is not True:
                raise ValueError("Reachability")
        return LocalRuntimeStatus(
            available=available,
            profile=string(payload, "Profile", nonempty=True),
            capability_score=score,
            model=string(payload, "Model", nonempty=available),
            reason=string(payload, "Reason", nonempty=True),
            ram_gb=number(memory, "total_gb"),
            gpu_name=string(gpu, "name"),
            vram_gb=number(gpu, "vram_gb"),
            num_ctx=number(payload, "NumCtx", integer=True, positive=True),
            num_predict=number(payload, "NumPredict", integer=True, positive=True),
        )
