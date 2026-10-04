"""Verify the fixed v1 reference baseline without executing manifest commands."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib


PRESENT = ["list_empty", "argparse_help"]
MISSING = ["add", "complete", "remove", "persistence", "stable_ids",
           "status_persistence", "env_override", "default_storage_file", "taskcli_gitignore_rule"]
# Filled from the reviewed baseline source; changing product behavior requires a new version.
PRODUCT_SHA256 = {
    "taskcli/__init__.py": "738826142f32be4356a098b50538392edccb804245b8f559499c083a4855b608",
    "taskcli/__main__.py": "68a9c9711327fcc6506b2dd5f0394686fb599776da43ec6225379c461a170428",
}
EXPECTED = {
    "schema_version": 1,
    "project_id": "python-task-cli-v1",
    "version": "1.0.0",
    "root": ".",
    "language": "python",
    "python_requires": ">=3.11",
    "cli": {"argv": ["python", "-B", "-m", "taskcli", "list"],
            "expected_stdout": "No tasks.\n", "expected_stderr": "", "expected_exit_code": 0},
    "baseline_tests": {"argv": ["python", "-B", "-m", "unittest", "discover", "-s", "tests", "-v"],
                       "expected_test_count": 5, "expected_exit_code": 0},
    "capabilities": {"PRESENT": PRESENT, "INTENTIONALLY_MISSING": MISSING},
    "missing_storage_contract": {"environment_variable": "TASKCLI_DATA_FILE", "default_path": ".taskcli/tasks.json"},
    "preflight": {
        "argv": ["python", "-B", "preflight.py"],
        "requires": ["Python >=3.11", "Git"],
        "required_files": ["acceptance-project.json", "README.md", ".gitignore", "pyproject.toml", "preflight.py",
                           "taskcli/__init__.py", "taskcli/__main__.py", "tests/test_cli.py"],
        "forbidden_artifacts": [".taskcli"],
        "product_source_sha256": PRODUCT_SHA256,
        "hash_normalization": "UTF-8 text with CRLF normalized to LF",
    },
}


class PreflightError(ValueError):
    """The project no longer represents the approved reference baseline."""


def check_gitignore(root: Path) -> None:
    """Use Git's ignore semantics in a disposable repo, never the product repo."""
    git = shutil.which("git")
    if not git:
        raise PreflightError("Git is required for taskcli_gitignore_rule preflight")
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_SYSTEM=os.devnull,
               GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0")
    with tempfile.TemporaryDirectory(prefix="taskcli-ignore-preflight-") as directory:
        probe = Path(directory)
        (probe / ".gitignore").write_bytes((root / ".gitignore").read_bytes())
        (probe / ".taskcli").mkdir()
        template = probe / "empty-template"
        template.mkdir()
        args = [git, "-c", f"core.excludesFile={os.devnull}"]
        initialized = subprocess.run([*args, "init", "--quiet", f"--template={template}"],
                                     cwd=probe, env=env, capture_output=True, timeout=30)
        if initialized.returncode:
            raise PreflightError("Cannot initialize isolated taskcli_gitignore_rule probe")
        for target in (".taskcli/", ".taskcli/tasks.json"):
            result = subprocess.run([*args, "check-ignore", "--no-index", "--quiet", target],
                                    cwd=probe, env=env, capture_output=True, timeout=30)
            if result.returncode == 0:
                raise PreflightError(f"Intentionally missing capability taskcli_gitignore_rule is implemented: {target} is effectively ignored")
            if result.returncode != 1:
                raise PreflightError("Git taskcli_gitignore_rule probe failed")


def check(root: Path) -> dict[str, object]:
    root = root.resolve()
    if sys.version_info < (3, 11):
        raise PreflightError("Python >=3.11 is required")
    required = EXPECTED["preflight"]["required_files"]
    for relative in required:
        path = root / relative
        if not path.is_file() or path.is_symlink():
            raise PreflightError(f"Missing regular baseline file: {relative}")
    try:
        manifest = json.loads((root / "acceptance-project.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise PreflightError(f"Invalid acceptance contract: {exc}") from exc
    if manifest != EXPECTED:
        raise PreflightError("Contract does not describe the fixed v1 baseline")
    package = tomllib.loads((root / "pyproject.toml").read_text(encoding="utf-8"))
    metadata = package.get("project", {})
    if metadata.get("version") != EXPECTED["version"] or metadata.get("requires-python") != EXPECTED["python_requires"]:
        raise PreflightError("Product package metadata contradicts the acceptance contract")
    if metadata.get("dependencies") != [] or package.get("tool", {}).get("setuptools", {}).get("packages") != ["taskcli"]:
        raise PreflightError("Baseline must expose only taskcli with no runtime dependencies")
    for relative, expected in PRODUCT_SHA256.items():
        normalized = (root / relative).read_text(encoding="utf-8").replace("\r\n", "\n").encode("utf-8")
        if hashlib.sha256(normalized).hexdigest() != expected:
            raise PreflightError(f"Product source drift: {relative}")
    if (root / ".taskcli").exists():
        raise PreflightError("Unexpected persistent .taskcli storage")
    check_gitignore(root)
    with tempfile.TemporaryDirectory(prefix="taskcli-preflight-") as directory:
        sentinel = Path(directory) / "external-data.json"
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["TASKCLI_DATA_FILE"] = str(sentinel)
        env.pop("PYTHONPATH", None)
        def run(*args: str) -> subprocess.CompletedProcess[bytes]:
            result = subprocess.run([sys.executable, "-B", "-m", *args], cwd=root,
                                    env=env, capture_output=True, timeout=30)
            if sentinel.exists() or (root / ".taskcli").exists():
                raise PreflightError("Baseline unexpectedly created task storage")
            return result
        cli = run("taskcli", "list")
        if (cli.returncode, cli.stdout, cli.stderr) != (0, b"No tasks.\n", b""):
            raise PreflightError("CLI list differs from the empty baseline")
        for command in ("add", "complete", "remove"):
            unsupported = run("taskcli", command, "probe")
            if unsupported.returncode != 2 or b"invalid choice" not in unsupported.stderr:
                raise PreflightError(f"Intentionally missing command unexpectedly accepted: {command}")
        tests = run("unittest", "discover", "-s", "tests", "-v")
        if tests.returncode != 0 or b"Ran 5 tests" not in tests.stderr or not tests.stderr.rstrip().endswith(b"OK"):
            raise PreflightError("Five positive baseline tests must pass")
    return {"status": "PASS", "project_id": EXPECTED["project_id"],
            "version": EXPECTED["version"], "baseline_tests": 5,
            "missing_features": MISSING, "provider_calls": 0}


def main() -> int:
    try:
        print(json.dumps(check(Path(__file__).resolve().parent), sort_keys=True))
        return 0
    except (PreflightError, OSError, subprocess.TimeoutExpired) as exc:
        print(f"PREFLIGHT FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
