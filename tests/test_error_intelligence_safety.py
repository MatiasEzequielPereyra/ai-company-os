"""Boundary tests using disposable databases and synthetic credentials only."""

import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

import pytest

from company_os.error_intelligence import ErrorIntelligenceStore, InvalidIncidentError, StoreBusyError, StoreCorruptError
from company_os.error_intelligence import store as store_module


def record(store):
    return store.record_incident(project_id="project", component="worker", category="runtime", error_type="Timeout", summary="Request timed out", evidence=["Synthetic deterministic test observation"])


def child_environment():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = str(Path(__file__).resolve().parents[1] / "src")
    return environment


def test_simultaneous_process_initialization_and_writes(tmp_path):
    path = tmp_path / "new.sqlite3"
    gate = tmp_path / "start"
    code = '''
import sys,time
from pathlib import Path
from company_os.error_intelligence import ErrorIntelligenceStore
path,gate,ready,index = sys.argv[1:]
Path(ready).touch()
deadline=time.monotonic()+15
while not Path(gate).exists():
    if time.monotonic()>deadline: raise RuntimeError('test start deadline')
    time.sleep(.01)
store=ErrorIntelligenceStore(path)
incident=store.record_incident(project_id='project',component='worker',category='runtime',error_type='Timeout',summary='Request timed out',evidence=['process '+index],run_id='run-'+index)
print(incident.id)
'''
    processes = [subprocess.Popen([sys.executable, "-c", code, str(path), str(gate), str(tmp_path / f"ready-{n}"), str(n)], env=child_environment(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for n in range(6)]
    try:
        deadline = time.monotonic() + 15
        while len(list(tmp_path.glob("ready-*"))) != 6 and time.monotonic() < deadline:
            time.sleep(.01)
        assert len(list(tmp_path.glob("ready-*"))) == 6
        gate.touch()
        outputs = [process.communicate(timeout=20) for process in processes]
        assert [process.returncode for process in processes] == [0] * 6, outputs
        assert len({stdout.strip() for stdout, _ in outputs}) == 1
        store = ErrorIntelligenceStore(path)
        incident = store.search(project_id="project")[0].incident
        assert incident.occurrence_count == 6
        assert {item.run_id for item in store.observations(incident.id)} == {f"run-{n}" for n in range(6)}
        with sqlite3.connect(path) as connection:
            assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
            assert not connection.execute("PRAGMA foreign_key_check").fetchall()
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def test_process_restart_preserves_installation_and_incident(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "restart.sqlite3")
    incident = record(store)
    code = "from company_os.error_intelligence import ErrorIntelligenceStore; import sys; i=ErrorIntelligenceStore(sys.argv[1]).get(sys.argv[2]); print(i.installation_id, i.id)"
    result = subprocess.run([sys.executable, "-c", code, str(store.path), incident.id], env=child_environment(), capture_output=True, text=True, timeout=15, check=True)
    assert result.stdout.strip() == f"{incident.installation_id} {incident.id}"


def test_lock_timeout_is_not_corruption_and_recovery_preserves_atomicity(tmp_path, monkeypatch):
    store = ErrorIntelligenceStore(tmp_path / "locked.sqlite3")
    original_connect = store._connect
    def short_timeout():
        connection = original_connect()
        connection.execute("PRAGMA busy_timeout=50")
        return connection
    monkeypatch.setattr(store, "_connect", short_timeout)
    holder = sqlite3.connect(store.path)
    try:
        holder.execute("BEGIN IMMEDIATE")
        with pytest.raises(StoreBusyError):
            record(store)
    finally:
        holder.rollback()
        holder.close()
    assert not store.search(project_id="project")
    assert record(store).occurrence_count == 1


def test_failed_event_append_rolls_back_incident_and_fix(tmp_path, monkeypatch):
    store = ErrorIntelligenceStore(tmp_path / "atomic.sqlite3")
    original_event = store._event
    def fail(*args, **kwargs):
        raise RuntimeError("synthetic interruption before commit")
    monkeypatch.setattr(store, "_event", fail)
    with pytest.raises(RuntimeError):
        record(store)
    assert not store.search(project_id="project")
    monkeypatch.setattr(store, "_event", original_event)
    incident = record(store)
    store.propose_fix(incident.id, action="Wait 30 seconds")
    monkeypatch.setattr(store, "_event", fail)
    with pytest.raises(RuntimeError):
        store.verify_fix(incident.id, action="Wait 30 seconds", verified_by="operator", evidence=["synthetic check passed"])
    assert store.get(incident.id).status == "FIX_PROPOSED"
    assert not store.verified_solutions(project_id="project")
    with sqlite3.connect(store.path) as connection:
        assert connection.execute("SELECT count(*) FROM recovery_attempts").fetchone()[0] == 0


def test_actions_with_different_numbers_are_not_interchangeable(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "actions.sqlite3")
    incident = record(store)
    store.propose_fix(incident.id, action="Wait 30 seconds")
    with pytest.raises(InvalidIncidentError):
        store.verify_fix(incident.id, action="Wait 90 seconds", verified_by="operator", evidence=["check"])
    store.verify_fix(incident.id, action="Wait 30 seconds", verified_by="operator", evidence=["check"])
    store.record_recovery_failure(incident.id, action="Wait 90 seconds", recorded_by="operator", evidence=["different action failed"])
    assert store.verified_solutions(project_id="project")


@pytest.mark.parametrize("text", [
    '{"api_key": "FAKE sensitive value with spaces"}',
    'GEMINI_API_KEY=FAKE_SECRET_VALUE_12345',
    "password='FAKE sensitive value with spaces'",
    'token: FAKE_SECRET_VALUE_12345',
    '-----BEGIN PRIVATE KEY-----\nFAKE_SECRET_VALUE_12345\n-----END PRIVATE KEY-----',
    'Authorization: Bearer FAKE_SECRET_VALUE_12345',
])
def test_secret_forms_never_reach_sqlite_pages(tmp_path, text):
    store = ErrorIntelligenceStore(tmp_path / "redacted.sqlite3")
    incident = store.record_incident(project_id="project", component="worker", category="runtime", error_type="Timeout", summary=text, evidence=[text])
    store.diagnose(incident.id, root_cause=text, evidence=[text])
    store.propose_fix(incident.id, action=text, contraindications=[text])
    store.verify_fix(incident.id, action=text, verified_by="operator", evidence=[text])
    assert b"FAKE_SECRET_VALUE_12345" not in store.path.read_bytes()
    assert b"FAKE sensitive value with spaces" not in store.path.read_bytes()


def test_stored_malformed_evidence_and_missing_verification_fail_closed(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "tampered.sqlite3")
    incident = record(store)
    with sqlite3.connect(store.path) as connection:
        connection.execute("UPDATE occurrences SET evidence_json='{}'")
    with pytest.raises(StoreCorruptError):
        store.get(incident.id)
    with sqlite3.connect(store.path) as connection:
        connection.execute('UPDATE occurrences SET evidence_json=?', ('["restored synthetic evidence"]',))
        connection.execute("UPDATE incidents SET status='FIX_VERIFIED', verified_fix='claimed fix', fix_verified_by='model', fix_evidence_json='[]'")
    with pytest.raises(StoreCorruptError):
        store.verified_solutions(project_id="project")


def test_future_schema_is_preserved(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "future.sqlite3")
    record(store)
    with sqlite3.connect(store.path) as connection:
        connection.execute("PRAGMA user_version=99")
    before = store.path.read_bytes()
    with pytest.raises(StoreCorruptError):
        ErrorIntelligenceStore(store.path)
    assert store.path.read_bytes() == before


def test_installation_paths_have_independent_memory(tmp_path, monkeypatch):
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    monkeypatch.delenv("AICO_ERROR_INTELLIGENCE_PATH", raising=False)
    monkeypatch.setattr(store_module, "__file__", str(tmp_path / "install-a" / "store.py"))
    first = ErrorIntelligenceStore()
    record(first)
    monkeypatch.setattr(store_module, "__file__", str(tmp_path / "install-b" / "store.py"))
    second = ErrorIntelligenceStore()
    assert first.path != second.path
    assert not second.search(project_id="project")


def test_windows_junction_is_rejected_before_creating_destination(tmp_path):
    if os.name != "nt":
        pytest.skip("Windows junction boundary")
    target = tmp_path / "target"
    target.mkdir()
    link = tmp_path / "junction"
    subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)], capture_output=True, check=True)
    try:
        with pytest.raises(InvalidIncidentError):
            ErrorIntelligenceStore(link / "new-directory" / "errors.sqlite3")
        assert not (target / "new-directory").exists()
    finally:
        link.rmdir()


def test_symlink_swap_after_initialization_is_rejected(tmp_path):
    store = ErrorIntelligenceStore(tmp_path / "original.sqlite3")
    target = tmp_path / "target.sqlite3"
    target.write_bytes(b"preserve target")
    store.path.unlink()
    try:
        store.path.symlink_to(target)
    except OSError:
        pytest.skip("OS account cannot create file symlinks")
    with pytest.raises(InvalidIncidentError):
        record(store)
    assert target.read_bytes() == b"preserve target"
