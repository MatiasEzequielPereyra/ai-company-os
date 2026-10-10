from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest
from typer.testing import CliRunner

from company_os.application.provider_service import ProviderService
from company_os.application.process_stream import run_streamed_process
from company_os.cli.app import app
from company_os.error_intelligence.runtime import capture_event, lookup


@pytest.fixture
def incident_project(tmp_path, monkeypatch):
    project = tmp_path / "project"
    project.mkdir()
    monkeypatch.setenv("AICO_ERROR_INTELLIGENCE_PATH", str(tmp_path / "memory.sqlite3"))
    monkeypatch.delenv("AICO_ERROR_INTELLIGENCE_ENABLED", raising=False)
    return project


def test_execution_environment_uses_current_installed_runtime(incident_project):
    environment = ProviderService().build_execution_environment(incident_project, workload="control")
    assert environment["AICO_ERROR_INTELLIGENCE_PYTHON"] == sys.executable
    root = Path(environment["AICO_ERROR_INTELLIGENCE_MODULE_ROOT"])
    assert (root / "company_os" / "error_intelligence" / "runtime.py").is_file()


def test_errors_cli_reads_automatic_observation(incident_project):
    captured = capture_event(incident_project, {"event_type": "runtime_failure", "component": "agent-runner"})
    result = CliRunner().invoke(app, ["errors", "--project", str(incident_project), "--json"])
    assert result.exit_code == 0, result.output
    payload = json.loads(result.output)
    assert payload["matches"][0]["id"] == captured["incident_id"]
    assert payload["action_authorized"] is False


def test_errors_cli_does_not_initialize_empty_store(incident_project):
    result = CliRunner().invoke(app, ["errors", "--project", str(incident_project), "--json"])
    assert result.exit_code == 0, result.output
    assert json.loads(result.output)["matches"] == []
    assert not (incident_project.parent / "memory.sqlite3").exists()


def test_process_launch_failure_keeps_original_and_captures(incident_project, monkeypatch):
    failure = OSError("private-token-must-not-be-stored")
    def reject(*args, **kwargs):
        raise failure
    monkeypatch.setattr(subprocess, "Popen", reject)
    command = ["missing", "-File", str(incident_project / "scripts" / "run-agent-task.ps1"),
               "-ProjectPath", str(incident_project), "-Id", "AICO-001"]
    messages = []
    with pytest.raises(OSError) as rejected:
        run_streamed_process(command, timeout=1, on_line=messages.append)
    assert rejected.value is failure
    history = lookup(incident_project)
    assert history["matches"][0]["error_type"] == "process_launch"
    assert history["matches"][0]["task_id"] == "AICO-001"
    assert "private-token" not in json.dumps(history)
    assert messages[0].startswith("Error Intelligence: incident=")


def test_memory_failure_does_not_replace_process_failure(incident_project, monkeypatch):
    database = incident_project.parent / "memory.sqlite3"
    database.write_bytes(b"corrupt preserved bytes")
    def reject(*args, **kwargs):
        raise FileNotFoundError("original launch failure")
    monkeypatch.setattr(subprocess, "Popen", reject)
    with pytest.raises(FileNotFoundError, match="original launch failure"):
        run_streamed_process(["missing", "-File", "run-gate-agent.ps1", "-ProjectPath", str(incident_project)], timeout=1)
    assert database.read_bytes() == b"corrupt preserved bytes"


def test_unrelated_process_is_not_captured(incident_project, monkeypatch):
    def reject(*args, **kwargs):
        raise OSError("unrelated")
    monkeypatch.setattr(subprocess, "Popen", reject)
    with pytest.raises(OSError):
        run_streamed_process(["missing", "-File", "other.ps1", "-ProjectPath", str(incident_project)], timeout=1)
    assert lookup(incident_project)["matches"] == []


def test_process_timeout_records_only_typed_metadata(incident_project, monkeypatch):
    import company_os.application.process_stream as module
    class HungProcess:
        stdout = iter(())
        killed = False
        def kill(self):
            self.killed = True
    process = HungProcess()
    monkeypatch.setattr(subprocess, "Popen", lambda *args, **kwargs: process)
    clock = iter((0.0, 2.0))
    monkeypatch.setattr(module.time, "monotonic", lambda: next(clock))
    command = ["host", "-File", "run-writable-agent.ps1", "-ProjectPath", str(incident_project)]
    with pytest.raises(subprocess.TimeoutExpired):
        run_streamed_process(command, timeout=1)
    assert process.killed
    match = lookup(incident_project)["matches"][0]
    assert match["component"] == "writable-runner"
    assert match["error_type"] == "timeout"


def test_doctor_surfaces_memory_without_capturing_or_mutating(incident_project, monkeypatch):
    from company_os.application.doctor_service import DoctorService
    import company_os.application.doctor_service as module
    capture_event(incident_project, {"event_type": "runtime_failure", "component": "gate-runner"})
    service = DoctorService()
    monkeypatch.setattr(service.status_service, "get_status", lambda project: object())
    monkeypatch.setattr(module, "analyze_snapshot", lambda snapshot: [])
    before = (incident_project.parent / "memory.sqlite3").read_bytes()
    findings = service.get_findings(incident_project)
    assert findings[0].code == "ERROR_INTELLIGENCE_HISTORY"
    assert (incident_project.parent / "memory.sqlite3").read_bytes() == before
