from __future__ import annotations

import json
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class LocalRuntimeStatus:
    available: bool
    profile: str
    capability_score: int
    model: str
    reason: str
    ram_gb: float
    gpu_name: str
    vram_gb: float
    num_ctx: int
    num_predict: int


class LocalRuntimeService:
    def __init__(
        self,
        cache_seconds: float = 30.0,
    ) -> None:
        self.cache_seconds = cache_seconds
        self._cache: dict[
            tuple[str, str, str],
            tuple[float, LocalRuntimeStatus],
        ] = {}

    def inspect(
        self,
        project_root: str | Path,
        role: str = "pm",
        workload: str = "analysis",
    ) -> LocalRuntimeStatus:
        root = Path(project_root).resolve()
        key = (
            str(root),
            role.strip().casefold(),
            workload.strip().casefold(),
        )

        cached = self._cache.get(key)
        now = time.monotonic()

        if (
            cached is not None
            and now - cached[0]
            < self.cache_seconds
        ):
            return cached[1]

        status = self._inspect_uncached(
            root,
            role,
            workload,
        )

        self._cache[key] = (
            now,
            status,
        )

        return status

    def invalidate(
        self,
        project_root: str | Path | None = None,
    ) -> None:
        if project_root is None:
            self._cache.clear()
            return

        root = str(
            Path(project_root).resolve()
        )

        for key in list(self._cache):
            if key[0] == root:
                self._cache.pop(
                    key,
                    None,
                )

    def _inspect_uncached(
        self,
        root: Path,
        role: str,
        workload: str,
    ) -> LocalRuntimeStatus:
        script = (
            root
            / "scripts"
            / "local-runtime"
            / "resolve-local-runtime.ps1"
        )

        if not script.exists():
            return self._unavailable(
                "Local runtime is not installed in this project. "
                "Run scripts/update-runtime.ps1 from the AI Company OS "
                "engine against this project, then press F5."
            )

        powershell = self._powershell()

        if not powershell:
            return self._unavailable(
                "PowerShell runtime was not found."
            )

        command_text = (
            "$result = & "
            + self._ps_literal(str(script))
            + " -ProjectPath "
            + self._ps_literal(str(root))
            + " -Role "
            + self._ps_literal(role)
            + " -Workload "
            + self._ps_literal(workload)
            + "; $result | ConvertTo-Json "
            + "-Depth 20 -Compress"
        )

        try:
            process = subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    command_text,
                ],
                capture_output=True,
                text=True,
                timeout=20,
            )
        except (
            OSError,
            subprocess.TimeoutExpired,
        ) as exc:
            return self._unavailable(
                f"Local runtime inspection failed: {exc}"
            )

        if process.returncode != 0:
            detail = (
                (process.stderr or "").strip()
                or (process.stdout or "").strip()
                or "Unknown local runtime error."
            )

            return self._unavailable(
                detail
            )

        payload = self._last_json_object(
            process.stdout or ""
        )

        if payload is None:
            return self._unavailable(
                "Local runtime returned no JSON status."
            )

        hardware = payload.get(
            "Hardware"
        ) or {}

        memory = hardware.get(
            "memory"
        ) or {}

        gpu = hardware.get(
            "gpu"
        ) or {}

        return LocalRuntimeStatus(
            available=bool(
                payload.get(
                    "Available",
                    False,
                )
            ),
            profile=str(
                payload.get(
                    "Profile",
                    "",
                )
            ),
            capability_score=int(
                payload.get(
                    "CapabilityScore",
                    0,
                )
                or 0
            ),
            model=str(
                payload.get(
                    "Model",
                    "",
                )
            ),
            reason=str(
                payload.get(
                    "Reason",
                    "",
                )
            ),
            ram_gb=float(
                memory.get(
                    "total_gb",
                    0.0,
                )
                or 0.0
            ),
            gpu_name=str(
                gpu.get(
                    "name",
                    "",
                )
            ),
            vram_gb=float(
                gpu.get(
                    "vram_gb",
                    0.0,
                )
                or 0.0
            ),
            num_ctx=int(
                payload.get(
                    "NumCtx",
                    0,
                )
                or 0
            ),
            num_predict=int(
                payload.get(
                    "NumPredict",
                    0,
                )
                or 0
            ),
        )

    @staticmethod
    def _last_json_object(
        output: str,
    ) -> dict | None:
        for line in reversed(
            output.splitlines()
        ):
            value = line.strip()

            if not value.startswith("{"):
                continue

            try:
                parsed = json.loads(
                    value
                )
            except json.JSONDecodeError:
                continue

            if isinstance(
                parsed,
                dict,
            ):
                return parsed

        return None

    @staticmethod
    def _ps_literal(
        value: str,
    ) -> str:
        return "'" + value.replace(
            "'",
            "''",
        ) + "'"

    @staticmethod
    def _powershell() -> str | None:
        return (
            shutil.which(
                "powershell.exe"
            )
            or shutil.which(
                "powershell"
            )
            or shutil.which(
                "pwsh.exe"
            )
            or shutil.which(
                "pwsh"
            )
        )

    @staticmethod
    def _unavailable(
        reason: str,
    ) -> LocalRuntimeStatus:
        return LocalRuntimeStatus(
            available=False,
            profile="",
            capability_score=0,
            model="",
            reason=reason,
            ram_gb=0.0,
            gpu_name="",
            vram_gb=0.0,
            num_ctx=0,
            num_predict=0,
        )
