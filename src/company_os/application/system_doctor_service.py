from __future__ import annotations

import platform
import shutil
import subprocess
import sys

from company_os.domain.models import Diagnostic, DiagnosticSeverity


class SystemDoctorService:
    def get_findings(self) -> list[Diagnostic]:
        findings: list[Diagnostic] = []

        python_version = (
            f"{sys.version_info.major}."
            f"{sys.version_info.minor}."
            f"{sys.version_info.micro}"
        )

        python_ok = sys.version_info >= (3, 11)

        findings.append(
            Diagnostic(
                severity=(
                    DiagnosticSeverity.INFO
                    if python_ok
                    else DiagnosticSeverity.ERROR
                ),
                code=(
                    "PYTHON_OK"
                    if python_ok
                    else "PYTHON_TOO_OLD"
                ),
                message=f"Python {python_version}",
                source=sys.executable,
            )
        )

        findings.append(
            Diagnostic(
                severity=DiagnosticSeverity.INFO,
                code="PLATFORM",
                message=platform.platform(),
            )
        )

        self._check_command(
            findings,
            code="GIT",
            commands=["git"],
            args=["--version"],
            required=False,
        )

        self._check_command(
            findings,
            code="NODE",
            commands=["node"],
            args=["--version"],
            required=False,
        )

        self._check_command(
            findings,
            code="NPM",
            commands=["npm"],
            args=["--version"],
            required=False,
        )

        self._check_command(
            findings,
            code="POWERSHELL",
            commands=["pwsh", "powershell"],
            args=[
                "-NoLogo",
                "-NoProfile",
                "-Command",
                "$PSVersionTable.PSVersion.ToString()",
            ],
            required=True,
        )

        self._check_ollama(findings)

        return findings

    def _check_command(
        self,
        findings: list[Diagnostic],
        *,
        code: str,
        commands: list[str],
        args: list[str],
        required: bool,
    ) -> None:
        executable = None

        for command in commands:
            executable = shutil.which(command)
            if executable:
                break

        if executable is None:
            findings.append(
                Diagnostic(
                    severity=(
                        DiagnosticSeverity.ERROR
                        if required
                        else DiagnosticSeverity.WARNING
                    ),
                    code=f"{code}_MISSING",
                    message=(
                        f"{code} was not found in PATH."
                    ),
                )
            )
            return

        try:
            result = subprocess.run(
                [executable, *args],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )

            output = (
                result.stdout.strip()
                or result.stderr.strip()
                or "available"
            )

            severity = (
                DiagnosticSeverity.INFO
                if result.returncode == 0
                else DiagnosticSeverity.WARNING
            )

            findings.append(
                Diagnostic(
                    severity=severity,
                    code=(
                        f"{code}_OK"
                        if result.returncode == 0
                        else f"{code}_ERROR"
                    ),
                    message=output.splitlines()[0],
                    source=executable,
                )
            )

        except Exception as exc:
            findings.append(
                Diagnostic(
                    severity=DiagnosticSeverity.WARNING,
                    code=f"{code}_ERROR",
                    message=str(exc),
                    source=executable,
                )
            )

    def _check_ollama(
        self,
        findings: list[Diagnostic],
    ) -> None:
        executable = shutil.which("ollama")

        if executable is None:
            findings.append(
                Diagnostic(
                    severity=DiagnosticSeverity.WARNING,
                    code="OLLAMA_MISSING",
                    message=(
                        "Ollama was not found in PATH. "
                        "Local automatic AI execution will not be available."
                    ),
                )
            )
            return

        try:
            result = subprocess.run(
                [executable, "list"],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
        except Exception as exc:
            findings.append(
                Diagnostic(
                    severity=DiagnosticSeverity.WARNING,
                    code="OLLAMA_ERROR",
                    message=str(exc),
                    source=executable,
                )
            )
            return

        if result.returncode != 0:
            findings.append(
                Diagnostic(
                    severity=DiagnosticSeverity.WARNING,
                    code="OLLAMA_ERROR",
                    message=(
                        result.stderr.strip()
                        or "Ollama is installed but unavailable."
                    ),
                    source=executable,
                )
            )
            return

        lines = [
            line.strip()
            for line in result.stdout.splitlines()
            if line.strip()
        ]

        models = lines[1:] if len(lines) > 1 else []

        findings.append(
            Diagnostic(
                severity=DiagnosticSeverity.INFO,
                code="OLLAMA_OK",
                message=(
                    f"Ollama available with "
                    f"{len(models)} installed model(s)."
                ),
                source=executable,
            )
        )

        default_model = "qwen3:8b"

        if any(
            line.split()[0] == default_model
            for line in models
            if line.split()
        ):
            findings.append(
                Diagnostic(
                    severity=DiagnosticSeverity.INFO,
                    code="OLLAMA_DEFAULT_MODEL_OK",
                    message=(
                        f"Default local model "
                        f"{default_model} is installed."
                    ),
                )
            )
        else:
            findings.append(
                Diagnostic(
                    severity=DiagnosticSeverity.WARNING,
                    code="OLLAMA_DEFAULT_MODEL_MISSING",
                    message=(
                        f"Default local model "
                        f"{default_model} is not installed."
                    ),
                )
            )