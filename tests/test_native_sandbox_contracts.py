"""Synthetic data only: no candidate programs, broker, VM or provider calls."""
from __future__ import annotations

import hashlib
import json
import struct
from datetime import datetime, timezone

import pytest

from company_os.sandbox.contracts import (
    ContractError, FileEntry, MAX_COMMAND_OUTPUT, MAX_FILE, MAX_MANIFEST,
    MAX_RECEIPT, MAX_TOTAL, sha256, snapshot_root, validate_path,
    validate_receipt, validate_request,
)

NOW = datetime(2026, 10, 15, 12, tzinfo=timezone.utc)
H = "a" * 64


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def make_request(payloads=None):
    payloads = {"tests/test_example.py": b"synthetic bytes only"} if payloads is None else payloads
    entries = [FileEntry(p, len(data), sha256(data)) for p, data in payloads.items()]
    request = {
        "schema": "aico.sandbox.request.v1",
        "repository_id": "MatiasEzequielPereyra/ai-company-os",
        "task_id": "AICO-9001",
        "attempt_id": "11111111-1111-4111-8111-111111111111",
        "execution_id": "22222222-2222-4222-8222-222222222222",
        "phase": "VERIFICATION",
        "created_utc": "2026-10-15T11:59:00Z",
        "expires_utc": "2026-10-15T12:15:00Z",
        "authorization_fingerprint": H, "scope_fingerprint": H,
        "dependencies_fingerprint": H, "lease_binding_id": "binding-001",
        "base_sha": "5ce38da9281ddb4baaef4654a35cad447979f8a1",
        "worktree_registration_id": "worktree-001",
        "snapshot_id": "33333333-3333-4333-8333-333333333333",
        "snapshot_root_sha256": snapshot_root(tuple(entries)),
        "image_id": "windows-native-v1", "image_sha256": H,
        "supervisor_sha256": H, "dependency_inventory_sha256": H,
        "policy_id": "native-offline-v1", "policy_sha256": H,
        "compatibility_profile_id": "win11-25h2-x64-v1",
        "files": [vars(f) for f in entries],
        "file_count": len(entries), "total_bytes": sum(f.size for f in entries),
        "commands": [{"command_id": "verify-001", "tool_id": "python-3.12",
                      "argv": ["-m", "pytest", "tests/test_example.py"],
                      "cwd": ".", "timeout_seconds": 300}],
        "limits": {"memory_mib": 4096, "vcpus": 2, "scratch_mib": 8192,
                   "processes": 128, "execution_seconds": 900, "output_bytes": 16777216},
        "network": "DENY", "host_mounts": [],
        "environment_profile_id": "minimal-offline-v1",
    }
    return request, payloads


def check_request(request, payloads):
    raw = encode(request)
    return validate_request(raw, manifest_sha256=sha256(raw), payloads=payloads, now=NOW)


def make_receipt(request):
    result = {
        "schema": "aico.sandbox.receipt.v1",
        **{key: getattr(request, key) for key in (
            "repository_id", "task_id", "attempt_id", "execution_id", "snapshot_id",
            "snapshot_root_sha256", "image_sha256", "policy_sha256")},
        "request_sha256": request.manifest_sha256,
        "guest_result": {"commands": [{
            "command_id": "verify-001", "exit_code": 0,
            "stdout_sha256": sha256(b"ok"), "stderr_sha256": sha256(b""),
            "stdout_bytes": 2, "stderr_bytes": 0, "output_complete": True,
        }], "source_integrity": "UNCHANGED"},
        "broker_observation": {"termination": "NORMAL", "cleanup": "CONFIRMED",
                               "cleanup_receipt_sha256": H},
        "acceptance": "ELIGIBLE_FOR_HOST_REVALIDATION",
    }
    return result, {"verify-001.stdout": b"ok", "verify-001.stderr": b""}


def check_receipt(result, request, outputs):
    raw = encode(result)
    return validate_receipt(raw, receipt_sha256=sha256(raw), request=request,
                            outputs=outputs, cleanup_receipt_sha256=H)


def test_round_trip_exact_bytes_and_immutable_result():
    request, payloads = make_request()
    parsed = check_request(request, payloads)
    receipt, outputs = make_receipt(parsed)
    checked = check_receipt(receipt, parsed, outputs)
    assert checked.execution_id == parsed.execution_id
    assert checked.raw == encode(receipt)
    request["task_id"] = "AICO-9999"
    assert parsed.task_id == "AICO-9001"
    with pytest.raises(AttributeError):
        parsed.task_id = "AICO-9999"


def test_binary_transcript_matches_independent_calculation():
    # Expected bytes built independently, including zero-byte and non-ASCII files.
    payloads = {"z.txt": b"", "café.txt": b"abc"}
    request, _ = make_request(payloads)
    transcript = b""
    for path in sorted(payloads, key=lambda p: p.encode("utf-8")):
        encoded = path.encode("utf-8")
        transcript += struct.pack(">I", len(encoded)) + encoded
        transcript += struct.pack(">Q", len(payloads[path])) + hashlib.sha256(payloads[path]).digest()
    assert request["snapshot_root_sha256"] == hashlib.sha256(transcript).hexdigest()
    check_request(request, payloads)


def test_empty_snapshot_and_directory_cwd():
    check_request(*make_request({}))
    request, payloads = make_request()
    request["commands"][0]["cwd"] = "tests"
    check_request(request, payloads)


@pytest.mark.parametrize("path", [
    "../outside", "a/../b", "a/./b", "/root", "//server/share", "C:/file",
    "C:file", "a\\b", "a:stream", "\\\\?\\C:\\file", "a//b", "a/", "",
    "CON", "con.txt", "CON .txt", "NUL.py", "COM1.log", "lpt².txt", "CONIN$", "a.", "a ",
    "a\x00b", "a\nb", "a\u202eb", "a\ud800", "a?b", "a*b", "a|b", "a<b", "a>b",
    'a"b', "a~1/b", "cafe\u0301.txt", "x" * 181,
    ".git/config", "src/.git/config", ".codex/policy", "tasks/AICO-9001.md",
    "docs/engineering/work-requests/WR-001.md", ".env.local", "src/secret.txt", "a.pem",
])
def test_windows_path_rejections(path):
    with pytest.raises(ContractError):
        validate_path(path)


@pytest.mark.parametrize("path", ["src/main.py", "café/test.py", "测试/a.txt", "src/COM10.txt", "a" * 180])
def test_windows_path_acceptance(path):
    assert validate_path(path) == path


@pytest.mark.parametrize("field,value", [
    ("schema", "aico.sandbox.request.v2"), ("schema", []),
    ("repository_id", "../../repo"), ("task_id", "NATIVE-SBX-001"),
    ("attempt_id", "not-a-uuid"), ("execution_id", "0" * 36),
    ("snapshot_id", "00000000-0000-0000-0000-000000000000"),
    ("phase", "RUN_COMMAND"), ("phase", {}), ("network", "ALLOW"),
    ("host_mounts", ["C:/"]), ("host_mounts", {}),
    ("authorization_fingerprint", "A" * 64), ("policy_sha256", "f" * 63),
    ("image_sha256", "<approved-sha256>"), ("base_sha", "main"),
    ("created_utc", "2026-10-15T13:00:00Z"),
    ("expires_utc", "2026-10-15T12:00:00Z"),
    ("expires_utc", "2026-02-30T12:00:00Z"),
    ("expires_utc", "2026-10-15T12:01:00+00:00"),
    ("file_count", True), ("file_count", 1.0), ("file_count", "1"),
    ("file_count", 2), ("file_count", 20001), ("total_bytes", -1),
    ("total_bytes", MAX_TOTAL + 1), ("snapshot_root_sha256", "0" * 64),
    ("lease_binding_id", "binding\n"), ("image_id", "../image"),
])
def test_request_fields_reject(field, value):
    request, payloads = make_request()
    request[field] = value
    with pytest.raises(ContractError):
        check_request(request, payloads)


@pytest.mark.parametrize("field", list(make_request()[0]))
def test_every_request_field_is_required(field):
    request, payloads = make_request()
    del request[field]
    with pytest.raises(ContractError):
        check_request(request, payloads)


@pytest.mark.parametrize("location", ["root", "file", "command", "limits"])
def test_unknown_fields_rejected_at_each_request_object(location):
    request, payloads = make_request()
    target = {"root": request, "file": request["files"][0],
              "command": request["commands"][0], "limits": request["limits"]}[location]
    target["extra"] = True
    with pytest.raises(ContractError, match="OBJECT_FIELDS"):
        check_request(request, payloads)


@pytest.mark.parametrize("location", ["root", "file", "command", "limits"])
def test_duplicate_keys_even_identical_or_escaped_are_rejected(location):
    request, payloads = make_request()
    raw = encode(request)
    key = {"root": "schema", "file": "path", "command": "command_id", "limits": "vcpus"}[location]
    target = {"root": request, "file": request["files"][0], "command": request["commands"][0], "limits": request["limits"]}[location]
    needle = encode(key) + b":" + encode(target[key])
    escaped_key = '"\\u%04x%s"' % (ord(key[0]), key[1:])
    raw = raw.replace(needle, needle + b"," + escaped_key.encode() + b":" + encode(target[key]), 1)
    with pytest.raises(ContractError, match="DUPLICATE_KEY"):
        validate_request(raw, manifest_sha256=sha256(raw), payloads=payloads, now=NOW)


@pytest.mark.parametrize("raw", [b"[]", b"{} trailing", b"\xff", b"\xef\xbb\xbf{}", b'{"x":NaN}', b'{"x":Infinity}', b'{"x":-Infinity}', b"[" * 2000])
def test_invalid_json(raw):
    with pytest.raises(ContractError):
        validate_request(raw, manifest_sha256=sha256(raw), payloads={}, now=NOW)


def test_document_hash_is_exact_bytes_not_reserialized_json():
    request, payloads = make_request()
    raw = encode(request)
    with pytest.raises(ContractError, match="DOCUMENT_HASH"):
        validate_request(raw + b" ", manifest_sha256=sha256(raw), payloads=payloads, now=NOW)
    validate_request(raw + b" ", manifest_sha256=sha256(raw + b" "), payloads=payloads, now=NOW)


@pytest.mark.parametrize("size", [MAX_FILE + 1, -1, True, "20"])
def test_invalid_file_sizes(size):
    request, payloads = make_request()
    request["files"][0]["size"] = size
    with pytest.raises(ContractError):
        check_request(request, payloads)


def test_payload_hash_reference_and_size_tampering():
    request, payloads = make_request()
    for bad in ({}, {**payloads, "extra": b""}, {next(iter(payloads)): b"modified"}, {next(iter(payloads)): bytearray(b"x")}):
        with pytest.raises(ContractError):
            check_request(request, bad)
    request["files"][0]["sha256"] = "0" * 64
    with pytest.raises(ContractError, match="FILE_HASH"):
        check_request(request, payloads)


@pytest.mark.parametrize("paths", [("a.py", "A.py"), ("Straße.py", "STRASSE.py"), ("a", "A/b"), ("i.py", "ı.py"), ("i", "ı/b")])
def test_path_collisions(paths):
    request, payloads = make_request({p: b"" for p in paths})
    with pytest.raises(ContractError, match="PATH_(?:PARENT_)?COLLISION"):
        check_request(request, payloads)


@pytest.mark.parametrize("field,value", [
    ("argv", [1]), ("argv", "-m pytest"), ("argv", ["x"] * 129),
    ("argv", ["x" * 32769]), ("argv", ["x\n"]), ("argv", ["x\u0000"]),
    ("tool_id", "python.exe;evil"), ("cwd", "../other"), ("cwd", "missing"),
    ("timeout_seconds", 301), ("timeout_seconds", 0), ("timeout_seconds", True),
])
def test_command_rejections(field, value):
    request, payloads = make_request()
    request["commands"][0][field] = value
    with pytest.raises(ContractError):
        check_request(request, payloads)


def test_command_count_duplicates_argument_total_and_budget():
    for mutate in (
        lambda r: r.update(commands=[]),
        lambda r: r.update(commands=r["commands"] * 13),
        lambda r: r.update(commands=r["commands"] * 2),
        lambda r: r["commands"][0].update(argv=["x" * 20000] * 2),
        lambda r: r["limits"].update(execution_seconds=299),
    ):
        request, payloads = make_request()
        mutate(request)
        with pytest.raises(ContractError):
            check_request(request, payloads)


@pytest.mark.parametrize("field,maximum", [("memory_mib", 4096), ("vcpus", 2), ("scratch_mib", 8192), ("processes", 128), ("execution_seconds", 900), ("output_bytes", 16777216)])
@pytest.mark.parametrize("kind", ["zero", "over", "boolean", "float"])
def test_resource_limit_rejections(field, maximum, kind):
    request, payloads = make_request()
    request["limits"][field] = {"zero": 0, "over": maximum + 1, "boolean": True, "float": 1.0}[kind]
    with pytest.raises(ContractError):
        check_request(request, payloads)


@pytest.mark.parametrize("field", ["repository_id", "task_id", "attempt_id", "execution_id", "snapshot_id", "request_sha256", "snapshot_root_sha256", "image_sha256", "policy_sha256"])
def test_receipt_identity_binding(field):
    parsed = check_request(*make_request())
    receipt, outputs = make_receipt(parsed)
    receipt[field] = "different"
    with pytest.raises(ContractError, match="RECEIPT_BINDING"):
        check_receipt(receipt, parsed, outputs)


@pytest.mark.parametrize("field", list(make_receipt(check_request(*make_request()))[0]))
def test_every_receipt_field_required(field):
    parsed = check_request(*make_request())
    receipt, outputs = make_receipt(parsed)
    del receipt[field]
    with pytest.raises(ContractError):
        check_receipt(receipt, parsed, outputs)


@pytest.mark.parametrize("location", ["root", "guest", "broker", "command"])
def test_receipt_unknown_and_duplicate_fields(location):
    parsed = check_request(*make_request())
    receipt, outputs = make_receipt(parsed)
    target = {"root": receipt, "guest": receipt["guest_result"], "broker": receipt["broker_observation"], "command": receipt["guest_result"]["commands"][0]}[location]
    key = next(iter(target))
    raw = encode(receipt)
    needle = encode(key) + b":" + encode(target[key])
    duplicate = raw.replace(needle, needle + b"," + needle, 1)
    with pytest.raises(ContractError, match="DUPLICATE_KEY"):
        validate_receipt(duplicate, receipt_sha256=sha256(duplicate), request=parsed, outputs=outputs, cleanup_receipt_sha256=H)
    target["unknown"] = "ignored?"
    with pytest.raises(ContractError, match="OBJECT_FIELDS"):
        check_receipt(receipt, parsed, outputs)


@pytest.mark.parametrize("mutation", [
    lambda r: r.update(schema="aico.sandbox.receipt.v2"),
    lambda r: r.update(acceptance="ACCEPTED"),
    lambda r: r["broker_observation"].update(cleanup="UNCONFIRMED"),
    lambda r: r["broker_observation"].update(cleanup_receipt_sha256="b" * 64),
    lambda r: r["broker_observation"].update(termination="TIMED_OUT"),
    lambda r: r["guest_result"].update(source_integrity="CHANGED"),
    lambda r: r["guest_result"].update(commands=[]),
    lambda r: r["guest_result"]["commands"][0].update(command_id="other"),
    lambda r: r["guest_result"]["commands"][0].update(exit_code=True),
    lambda r: r["guest_result"]["commands"][0].update(exit_code=2**32),
    lambda r: r["guest_result"]["commands"][0].update(stdout_sha256="0" * 64),
    lambda r: r["guest_result"]["commands"][0].update(stdout_bytes=3),
    lambda r: r["guest_result"]["commands"][0].update(output_complete=False),
    lambda r: r["guest_result"]["commands"][0].update(output_complete=1),
])
def test_receipt_rejections(mutation):
    parsed = check_request(*make_request())
    receipt, outputs = make_receipt(parsed)
    mutation(receipt)
    with pytest.raises(ContractError):
        check_receipt(receipt, parsed, outputs)


def test_rejected_sealed_receipt_and_nonzero_diagnostic_exit():
    request, payloads = make_request()
    request["phase"] = "REPRODUCTION"
    parsed = check_request(request, payloads)
    receipt, outputs = make_receipt(parsed)
    receipt["guest_result"]["commands"][0]["exit_code"] = 1
    check_receipt(receipt, parsed, outputs)  # Integrity is not an assertion of PASS.
    receipt["acceptance"] = "REJECTED"
    receipt["broker_observation"]["termination"] = "CANCELLED"
    receipt["guest_result"]["commands"] = []
    check_receipt(receipt, parsed, {})


def test_output_references_and_limits():
    parsed = check_request(*make_request())
    receipt, outputs = make_receipt(parsed)
    with pytest.raises(ContractError):
        check_receipt(receipt, parsed, {**outputs, "other.stdout": b""})
    record = receipt["guest_result"]["commands"][0]
    record["stdout_bytes"] = MAX_COMMAND_OUTPUT + 1
    with pytest.raises(ContractError):
        check_receipt(receipt, parsed, outputs)
    request, payloads = make_request()
    request["limits"]["output_bytes"] = 1
    parsed = check_request(request, payloads)
    receipt, outputs = make_receipt(parsed)
    with pytest.raises(ContractError, match="TOTAL_OUTPUT_LIMIT"):
        check_receipt(receipt, parsed, outputs)


def test_document_size_limits_without_large_external_files():
    for maximum, is_receipt in ((MAX_MANIFEST, False), (MAX_RECEIPT, True)):
        raw = b" " * (maximum + 1)
        with pytest.raises(ContractError, match="JSON_SIZE"):
            if is_receipt:
                validate_receipt(raw, receipt_sha256=sha256(raw), request=check_request(*make_request()), outputs={}, cleanup_receipt_sha256=H)
            else:
                validate_request(raw, manifest_sha256=sha256(raw), payloads={}, now=NOW)


def test_bytes_api_no_filesystem_resolution(tmp_path):
    # A manifest path is data; it must not cause the validator to open this file.
    sentinel = tmp_path / "sentinel.txt"
    sentinel.write_bytes(b"unchanged")
    request, payloads = make_request({"sentinel.txt": b"synthetic"})
    check_request(request, payloads)
    assert sentinel.read_bytes() == b"unchanged"
    with pytest.raises(ContractError):
        validate_request(encode(request).decode(), manifest_sha256=H, payloads=payloads, now=NOW)
    with pytest.raises(ContractError, match="HOST_TIME"):
        raw = encode(request)
        validate_request(raw, manifest_sha256=sha256(raw), payloads=payloads, now=NOW.replace(tzinfo=None))


def test_total_declared_payload_limit_before_reading_contents():
    request, payloads = make_request({f"f{i}": b"" for i in range(17)})
    for record in request["files"]:
        record["size"] = MAX_FILE
    request["total_bytes"] = 17 * MAX_FILE
    with pytest.raises(ContractError, match="TOTAL_BYTES|INTEGER_RANGE"):
        check_request(request, payloads)


def test_file_count_boundary():
    request, payloads = make_request({f"f{i}": b"" for i in range(20000)})
    check_request(request, payloads)
    request["files"].append({"path": "extra", "size": 0, "sha256": sha256(b"")})
    with pytest.raises(ContractError, match="FILE_COUNT"):
        check_request(request, payloads)


def test_command_limit_and_utf16_path_length():
    request, payloads = make_request()
    request["commands"] = [{**request["commands"][0], "command_id": f"c{i}"} for i in range(12)]
    check_request(request, payloads)
    rocket = chr(0x1F680)
    assert validate_path(rocket * 90) == rocket * 90
    with pytest.raises(ContractError, match="PATH_LENGTH"):
        validate_path(rocket * 91)


def test_combined_output_limit_is_not_per_stream():
    parsed = check_request(*make_request())
    receipt, outputs = make_receipt(parsed)
    record = receipt["guest_result"]["commands"][0]
    for stream in ("stdout", "stderr"):
        data = b"x" * (MAX_COMMAND_OUTPUT // 2 + 1)
        outputs["verify-001." + stream] = data
        record[stream + "_bytes"] = len(data)
        record[stream + "_sha256"] = sha256(data)
    with pytest.raises(ContractError, match="COMMAND_OUTPUT_LIMIT"):
        check_receipt(receipt, parsed, outputs)


def test_result_output_manipulation_and_receipt_raw_hash():
    parsed = check_request(*make_request())
    receipt, outputs = make_receipt(parsed)
    with pytest.raises(ContractError, match="OUTPUT_HASH"):
        check_receipt(receipt, parsed, {**outputs, "verify-001.stdout": b"no"})
    raw = encode(receipt)
    with pytest.raises(ContractError, match="DOCUMENT_HASH"):
        validate_receipt(raw + b" ", receipt_sha256=sha256(raw), request=parsed,
                         outputs=outputs, cleanup_receipt_sha256=H)


def test_empty_literal_argument_is_data():
    request, payloads = make_request()
    request["commands"][0]["argv"] = [""]
    assert check_request(request, payloads).commands[0].argv == ("",)


def test_maximum_file_size_is_accepted():
    request, payloads = make_request({"synthetic.bin": bytes(MAX_FILE)})
    check_request(request, payloads)


@pytest.mark.parametrize("command_count", [4, 5])
def test_aggregate_output_boundary(command_count):
    request, payloads = make_request()
    request["commands"] = [{**request["commands"][0], "command_id": f"c{i}"} for i in range(command_count)]
    parsed = check_request(request, payloads)
    receipt, _ = make_receipt(parsed)
    data = b"x" * MAX_COMMAND_OUTPUT
    records = []
    outputs = {}
    for i in range(command_count):
        cid = f"c{i}"
        records.append({"command_id": cid, "exit_code": 0, "stdout_bytes": len(data),
                        "stderr_bytes": 0, "stdout_sha256": sha256(data),
                        "stderr_sha256": sha256(b""), "output_complete": True})
        outputs[cid + ".stdout"] = data
        outputs[cid + ".stderr"] = b""
    receipt["guest_result"]["commands"] = records
    if command_count == 4:
        check_receipt(receipt, parsed, outputs)
    else:
        with pytest.raises(ContractError, match="TOTAL_OUTPUT_LIMIT"):
            check_receipt(receipt, parsed, outputs)


@pytest.mark.parametrize("mutation", [
    lambda r: r.update(files={}),
    lambda r: r.update(commands=True),
    lambda r: r.update(limits=[]),
    lambda r: r["files"][0].update(path=12),
    lambda r: r["commands"][0].update(cwd=[]),
    lambda r: r["commands"][0].update(command_id=False),
])
def test_nested_wrong_types_fail_closed(mutation):
    request, payloads = make_request()
    mutation(request)
    with pytest.raises(ContractError):
        check_request(request, payloads)


def test_no_filesystem_or_process_dependency_in_validator():
    # Review guard: adding operational imports requires an explicit scope change.
    import ast
    import inspect
    from company_os.sandbox import contracts

    tree = ast.parse(inspect.getsource(contracts))
    roots = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            roots.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            roots.add(node.module.split(".")[0])
    assert roots <= {"__future__", "hashlib", "json", "re", "struct", "unicodedata",
                     "collections", "dataclasses", "datetime", "uuid"}
    assert not any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                   and node.func.id in {"open", "eval", "exec", "compile", "__import__"}
                   for node in ast.walk(tree))


@pytest.mark.parametrize("path", [
    "AGENTS.md",
    ".agents/skills/code-review/SKILL.md",
    "scripts/run-writable-agent.ps1",
])
def test_snapshot_control_plane_review_reproduction(path):
    # Complete, correctly hashed request: rejection must concern export policy.
    request, payloads = make_request({path: b"synthetic control-plane bytes"})
    with pytest.raises(ContractError, match="SNAPSHOT_EXPORT_FORBIDDEN"):
        check_request(request, payloads)


@pytest.mark.parametrize("path", [
    "agents.MD", "src/AGENTS.md", "tests/fixtures/.AgEnTs/skills/x/SKILL.md",
    "nested/SCRIPTS/provider-router.ps1", "scrıpts/run-writable-agent.ps1",
    ".gıthub/workflows/ci.yml", "ıd_rsa", "src/tasks/AICO-001.md",
    "docs/architecture/design.md", "nested/docs/engineering/receipt.md",
    "schemas/task.schema.json", "templates/AGENTS.md", "acceptance/evidence.json",
    "npm-bin/company.js", ".github/workflows/ci.yml", "nested/.gitlab/pipeline.yml",
    ".circleci/config.yml", ".buildkite/pipeline.yml", ".devcontainer/devcontainer.json",
    ".vscode/settings.json", ".idea/workspace.xml", ".husky/pre-commit",
    "SECURITY.md", "src/CONTRIBUTING.md", "nested/CODEOWNERS",
    "governance/approval.json", "policies/sandbox.json", "broker/config.json",
    "runtime/settings.json", "services/broker.xml", "config/privileged.json",
    "infra/main.tf", "infrastructure/stack.yml", "deploy/service.yml",
    "deployment/service.yml", "ops/host.json", ".ssh/config", "src/.AWS/config",
    ".azure/profile.json", ".kube/config", ".gnupg/pubring.kbx",
    ".docker/config.json", ".config/tool/token", ".npmrc", "src/.pypirc",
    "nested/.netrc", "_netrc", ".gitconfig", ".gitmodules", ".gitattributes",
    ".git-credentials", ".yarnrc.yml", ".gitlab-ci.yml", "azure-pipelines.yml",
    "Jenkinsfile", "Dockerfile", "compose.yaml", "docker-compose.yml",
    "id_rsa", "nested/id_ed25519",
    ".codex/runtime/state.json", "docs/engineering/work-requests/WR-001.md",
    ".env", "src/credentials.json", "key.pem",
])
def test_snapshot_export_exclusions_on_complete_requests(path):
    request, payloads = make_request({"src/product.py": b"product", path: b"synthetic excluded data"})
    with pytest.raises(ContractError, match="SNAPSHOT_EXPORT_FORBIDDEN|PATH_PROTECTED|PATH_SECRET"):
        check_request(request, payloads)


@pytest.mark.parametrize("path", [
    "src/product.py", "src/app/config.py", "src/app/config/default.json",
    "tests/test_product.py", "tests/fixtures/input.json", "src/café.py",
    "package.json", "pyproject.toml", "requirements.txt",
    "scripts-example.py", "src/docs_parser.py", "tests/agents_test.py",
])
def test_product_and_test_snapshot_requests_remain_admissible(path):
    request, payloads = make_request({path: b"synthetic product/test data"})
    parsed = check_request(request, payloads)
    assert parsed.files[0].path == path


@pytest.mark.parametrize("field", ["policy_id", "policy_sha256", "compatibility_profile_id", "environment_profile_id"])
def test_manifest_policy_claim_cannot_enable_export_exception(field):
    request, payloads = make_request({"AGENTS.md": b"synthetic"})
    request[field] = "b" * 64 if field.endswith("sha256") else "allow-control-plane"
    with pytest.raises(ContractError, match="SNAPSHOT_EXPORT_FORBIDDEN"):
        check_request(request, payloads)


@pytest.mark.parametrize("field", ["export_policy", "allow_control_plane", "export_exceptions"])
def test_manifest_cannot_inject_export_policy_fields(field):
    request, payloads = make_request({"AGENTS.md": b"synthetic"})
    request[field] = ["AGENTS.md"]
    with pytest.raises(ContractError, match="OBJECT_FIELDS"):
        check_request(request, payloads)


def test_write_path_admission_is_not_snapshot_export_authority():
    # Preserve lexical API semantics; full requests must add C4 export policy.
    assert validate_path("AGENTS.md") == "AGENTS.md"
    assert validate_path("scripts/run-writable-agent.ps1") == "scripts/run-writable-agent.ps1"
    for path in ("AGENTS.md", "scripts/run-writable-agent.ps1"):
        with pytest.raises(ContractError, match="SNAPSHOT_EXPORT_FORBIDDEN"):
            check_request(*make_request({path: b"synthetic"}))
