"""Reference-project preflight checks; kept separate from its positive baseline."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest


REFERENCE = Path(__file__).resolve().parents[1] / "acceptance/reference-projects/python-task-cli-v1"
SPEC = importlib.util.spec_from_file_location("reference_preflight", REFERENCE / "preflight.py")
PREFLIGHT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREFLIGHT)


@pytest.fixture
def reference_copy(tmp_path):
    target = tmp_path / "reference"
    shutil.copytree(REFERENCE, target, ignore=shutil.ignore_patterns("__pycache__", ".pytest_cache"))
    return target


def test_canonical_preflight_preserves_files(reference_copy):
    before = {p.relative_to(reference_copy): p.read_bytes() for p in reference_copy.rglob("*") if p.is_file()}
    assert PREFLIGHT.check(reference_copy)["status"] == "PASS"
    after = {p.relative_to(reference_copy): p.read_bytes() for p in reference_copy.rglob("*") if p.is_file()}
    assert after == before


def test_missing_product_is_rejected(reference_copy):
    (reference_copy / "taskcli/__main__.py").unlink()
    with pytest.raises(PREFLIGHT.PreflightError, match="Missing regular baseline file"):
        PREFLIGHT.check(reference_copy)


def test_misleading_manifest_never_executes_commands(reference_copy):
    manifest_path = reference_copy / "acceptance-project.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["cli"]["argv"] = ["python", "-c", "raise RuntimeError('must not execute')"]
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(PREFLIGHT.PreflightError, match="Contract does not describe"):
        PREFLIGHT.check(reference_copy)


def test_implemented_missing_feature_is_rejected(reference_copy):
    entrypoint = reference_copy / "taskcli/__main__.py"
    entrypoint.write_text(entrypoint.read_text(encoding="utf-8").replace('commands.add_parser("list",', 'commands.add_parser("add")\n    commands.add_parser("list",'), encoding="utf-8")
    with pytest.raises(PREFLIGHT.PreflightError, match="Product source drift"):
        PREFLIGHT.check(reference_copy)


def test_persistent_storage_is_rejected(reference_copy):
    (reference_copy / ".taskcli").mkdir()
    with pytest.raises(PREFLIGHT.PreflightError, match="persistent .taskcli"):
        PREFLIGHT.check(reference_copy)


def test_crlf_checkout_is_supported(reference_copy):
    for relative in PREFLIGHT.PRODUCT_SHA256:
        path = reference_copy / relative
        path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
    assert PREFLIGHT.check(reference_copy)["status"] == "PASS"


def test_managed_company_runtime_does_not_change_baseline(reference_copy):
    (reference_copy / ".codex").mkdir()
    (reference_copy / ".codex/provider-config.json").write_text("{}", encoding="utf-8")
    (reference_copy / "scripts").mkdir()
    assert PREFLIGHT.check(reference_copy)["status"] == "PASS"


def test_missing_gitignore_is_rejected(reference_copy):
    (reference_copy / ".gitignore").unlink()
    with pytest.raises(PREFLIGHT.PreflightError, match="Missing regular baseline file: .gitignore"):
        PREFLIGHT.check(reference_copy)


def test_preflight_command_contract_cannot_be_overridden(reference_copy):
    manifest_path = reference_copy / "acceptance-project.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["preflight"]["argv"] = ["python", "unsafe.py"]
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(PREFLIGHT.PreflightError, match="Contract does not describe"):
        PREFLIGHT.check(reference_copy)


def test_package_version_mismatch_is_rejected(reference_copy):
    metadata = reference_copy / "pyproject.toml"
    metadata.write_text(metadata.read_text(encoding="utf-8").replace('version = "1.0.0"', 'version = "9.0.0"'), encoding="utf-8")
    with pytest.raises(PREFLIGHT.PreflightError, match="metadata contradicts"):
        PREFLIGHT.check(reference_copy)


@pytest.mark.parametrize("rule", [".taskcli/", ".taskcli", "/.taskcli/", ".task*/", "*\n!.taskcli/\n"])
def test_effective_taskcli_ignore_is_rejected(reference_copy, rule):
    with (reference_copy / ".gitignore").open("ab") as stream:
        stream.write(("\n" + rule + "\n").encode("utf-8"))
    result = subprocess.run([sys.executable, "-B", "preflight.py"], cwd=reference_copy,
                            capture_output=True, timeout=30)
    assert result.returncode == 1
    assert b"taskcli_gitignore_rule is implemented" in result.stderr
    assert not (reference_copy / ".git").exists()
    assert not (reference_copy / ".taskcli").exists()


@pytest.mark.parametrize("rule", ["# .taskcli/", ".taskcli/tasks.json\n!.taskcli/tasks.json", ".task*/\n!.taskcli/"])
def test_non_effective_ignore_patterns_are_allowed(reference_copy, rule):
    with (reference_copy / ".gitignore").open("ab") as stream:
        stream.write(("\n" + rule + "\n").encode("utf-8"))
    assert PREFLIGHT.check(reference_copy)["status"] == "PASS"


def test_ambient_git_configuration_is_not_used(reference_copy, tmp_path, monkeypatch):
    excludes = tmp_path / "global-ignore"
    excludes.write_text(".taskcli/\n", encoding="utf-8")
    config = tmp_path / "global-config"
    config.write_text('[core]\nexcludesFile = "' + excludes.as_posix() + '"\n', encoding="utf-8")
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", str(config))
    monkeypatch.setenv("GIT_CONFIG_COUNT", "1")
    monkeypatch.setenv("GIT_CONFIG_KEY_0", "core.excludesFile")
    monkeypatch.setenv("GIT_CONFIG_VALUE_0", str(excludes))
    monkeypatch.setenv("GIT_DIR", str(tmp_path / "must-not-be-used"))
    assert PREFLIGHT.check(reference_copy)["status"] == "PASS"
