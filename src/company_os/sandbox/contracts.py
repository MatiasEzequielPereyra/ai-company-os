"""Strict byte-level contracts for NATIVE-SBX-001.

No filesystem, subprocess, provider or Hyper-V access is performed here. Callers
supply payload bytes and independently obtained digests. Successful validation
proves data consistency only, never authorization, OS isolation or actual cleanup.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
import unicodedata
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import UUID

MIB = 1024 * 1024
MAX_MANIFEST = 8 * MIB
MAX_RECEIPT = MIB
MAX_FILES = 20_000
MAX_FILE = 64 * MIB
MAX_TOTAL = 1024 * MIB
MAX_COMMANDS = 12
MAX_COMMAND_OUTPUT = 4 * MIB
MAX_OUTPUT = 16 * MIB

PROTECTED_PREFIXES = (
    ".git", ".codex", "tasks", "docs/engineering/agent-reports",
    "docs/engineering/writable-evidence", "docs/engineering/diagnostics",
    "docs/engineering/dispatch", "docs/engineering/work-requests",
    "docs/engineering/plans", "docs/engineering/results",
    "docs/engineering/reviews", "docs/engineering/qa",
    "docs/engineering/security", "docs/engineering/final-approvals",
)
SECRET = re.compile(
    r"(^|/)\.env($|\.)|(^|/)[^/]*(?:secret|credential|private[-_]?key|service[-_]?account)"
    r"|\.(?:pem|key|p12|pfx)$", re.IGNORECASE,
)
# Export authority is separate from the runner's write-path restrictions above.
# This trusted, fixed V1 profile has no manifest-controlled exceptions. Reserved
# directory segments apply at every depth, including nested project/fixture copies.
SNAPSHOT_RESERVED_DIRECTORIES = frozenset({
    ".git", ".codex", ".agents", ".github", ".gitlab", ".circleci",
    ".buildkite", ".devcontainer", ".vscode", ".idea", ".husky",
    ".ssh", ".aws", ".azure", ".kube", ".gnupg", ".docker", ".config",
    "scripts", "tasks", "docs", "schemas", "templates", "acceptance", "npm-bin",
})
SNAPSHOT_RESERVED_ROOTS = frozenset({
    "governance", "policies", "broker", "runtime", "services", "config",
    "infra", "infrastructure", "deploy", "deployment", "ops",
})
SNAPSHOT_RESERVED_NAMES = frozenset({
    "agents.md", "security.md", "contributing.md", "codeowners",
    ".gitconfig", ".gitmodules", ".gitattributes", ".git-credentials",
    ".npmrc", ".yarnrc", ".yarnrc.yml", ".pypirc", ".netrc", "_netrc",
    ".gitlab-ci.yml", "azure-pipelines.yml", "azure-pipelines.yaml",
    "jenkinsfile", "dockerfile", "compose.yml", "compose.yaml",
    "docker-compose.yml", "docker-compose.yaml",
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
})
RESERVED = re.compile(r"^(?:con|prn|aux|nul|conin\$|conout\$|com[1-9¹²³]|lpt[1-9¹²³])$", re.I)
REQUEST_FIELDS = {
    "schema", "repository_id", "task_id", "attempt_id", "execution_id", "phase",
    "created_utc", "expires_utc", "authorization_fingerprint", "scope_fingerprint",
    "dependencies_fingerprint", "lease_binding_id", "base_sha",
    "worktree_registration_id", "snapshot_id", "snapshot_root_sha256", "image_id",
    "image_sha256", "supervisor_sha256", "dependency_inventory_sha256", "policy_id",
    "policy_sha256", "compatibility_profile_id", "files", "file_count", "total_bytes",
    "commands", "limits", "network", "host_mounts", "environment_profile_id",
}
RECEIPT_FIELDS = {
    "schema", "repository_id", "task_id", "attempt_id", "execution_id", "snapshot_id",
    "request_sha256", "snapshot_root_sha256", "image_sha256", "policy_sha256",
    "guest_result", "broker_observation", "acceptance",
}


class ContractError(ValueError):
    """A closed, non-sensitive rejection code (input values are never echoed)."""


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ContractError(code)


def _shape(value: object, fields: set[str]) -> dict:
    _require(type(value) is dict and value.keys() == fields, "OBJECT_FIELDS")
    return value


def _text(value: object, maximum: int = 128, *, allow_empty: bool = False) -> str:
    _require(type(value) is str, "STRING_TYPE")
    try:
        encoded = value.encode("utf-8")
    except UnicodeError:
        raise ContractError("UNICODE_INVALID") from None
    _require((allow_empty or len(encoded) > 0) and len(encoded) <= maximum, "STRING_LENGTH")
    _require(not any(unicodedata.category(c).startswith("C") for c in value), "STRING_CONTROL")
    return value


def _identifier(value: object) -> str:
    value = _text(value)
    _require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value) is not None, "IDENTIFIER")
    return value


def _uuid(value: object) -> str:
    value = _text(value, 36)
    try:
        parsed = UUID(value)
    except ValueError:
        raise ContractError("UUID") from None
    _require(str(parsed) == value and parsed.int != 0, "UUID")
    return value


def _integer(value: object, minimum: int, maximum: int) -> int:
    _require(type(value) is int and minimum <= value <= maximum, "INTEGER_RANGE")
    return value


def _digest(value: object) -> str:
    _require(type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value) is not None, "SHA256")
    return value


def sha256(data: bytes) -> str:
    _require(type(data) is bytes, "BYTES_REQUIRED")
    return hashlib.sha256(data).hexdigest()


def _pairs(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        _require(key not in result, "DUPLICATE_KEY")
        result[key] = value
    return result


def _bad_constant(_: str) -> None:
    raise ContractError("JSON_NONFINITE")


def _load(raw: bytes, maximum: int, expected_sha256: str) -> dict:
    _require(type(raw) is bytes, "BYTES_REQUIRED")
    _require(0 < len(raw) <= maximum, "JSON_SIZE")
    _require(not raw.startswith(b"\xef\xbb\xbf"), "JSON_BOM")
    _require(sha256(raw) == _digest(expected_sha256), "DOCUMENT_HASH")
    try:
        result = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs, parse_constant=_bad_constant)
    except (UnicodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
        if isinstance(exc, ContractError):
            raise
        raise ContractError("JSON_INVALID") from None
    _require(type(result) is dict, "OBJECT_TYPE")
    return result


def _utc(value: object) -> datetime:
    _require(type(value) is str and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", value) is not None, "UTC_FORMAT")
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        raise ContractError("UTC_INVALID") from None


def validate_path(value: object, *, source: bool = True) -> str:
    """Validate lexical Windows paths on every host OS; never normalize input."""
    path = _text(value, 720)
    _require(len(path.encode("utf-16-le")) // 2 <= 180, "PATH_LENGTH")
    _require(unicodedata.normalize("NFC", path) == path, "PATH_NFC")
    _require(not any(c in path for c in '\\:<>"|?*'), "PATH_SPECIAL")
    parts = path.split("/")
    for part in parts:
        _require(part not in ("", ".", "..") and not part.endswith((".", " ")), "PATH_SEGMENT")
        _require(RESERVED.fullmatch(part.split(".")[0].rstrip(" .")) is None, "PATH_DEVICE")
        # NTFS short-name aliases are not admitted by this lexical V1 profile.
        _require("~" not in part, "PATH_ALIAS")
    if source:
        lower = path.casefold()
        _require(not any(lower == p or lower.startswith(p + "/") for p in PROTECTED_PREFIXES), "PATH_PROTECTED")
        _require(not any(p.casefold() in (".git", ".codex") for p in parts), "PATH_PROTECTED")
        _require(SECRET.search(lower) is None, "PATH_SECRET")
    return path


def validate_snapshot_path(value: object) -> str:
    """Apply C4 export exclusions after lexical/source safety validation.

    A safe write path is not necessarily exportable. Policy IDs/fingerprints in
    a request never relax this profile. This is name-based admission only, not
    content classification or filesystem metadata inspection.
    """
    path = validate_path(value)
    # Uppercase first also excludes Windows ordinal aliases such as dotless-I.
    # All reserved tokens are ASCII; casefold alone would miss those aliases.
    parts = [part.upper().casefold() for part in path.split("/")]
    _require(
        not any(part in SNAPSHOT_RESERVED_DIRECTORIES for part in parts)
        and parts[0] not in SNAPSHOT_RESERVED_ROOTS
        and not any(part in SNAPSHOT_RESERVED_NAMES for part in parts),
        "SNAPSHOT_EXPORT_FORBIDDEN",
    )
    return path


@dataclass(frozen=True)
class FileEntry:
    path: str
    size: int
    sha256: str


@dataclass(frozen=True)
class Command:
    command_id: str
    tool_id: str
    argv: tuple[str, ...]
    cwd: str
    timeout_seconds: int


@dataclass(frozen=True)
class ValidatedRequest:
    raw: bytes
    manifest_sha256: str
    repository_id: str
    task_id: str
    attempt_id: str
    execution_id: str
    snapshot_id: str
    snapshot_root_sha256: str
    image_sha256: str
    policy_sha256: str
    files: tuple[FileEntry, ...]
    commands: tuple[Command, ...]
    output_limit: int


@dataclass(frozen=True)
class ValidatedReceipt:
    """Consistent data, not a signed broker attestation or permission to publish."""
    raw: bytes
    receipt_sha256: str
    execution_id: str
    acceptance: str


def snapshot_root(files: tuple[FileEntry, ...]) -> str:
    """C1 binary transcript: u32 path length, UTF-8 path, u64 size, raw digest."""
    digest = hashlib.sha256()
    for entry in sorted(files, key=lambda f: f.path.encode("utf-8")):
        path = entry.path.encode("utf-8")
        digest.update(struct.pack(">I", len(path)))
        digest.update(path)
        digest.update(struct.pack(">Q", _integer(entry.size, 0, MAX_FILE)))
        digest.update(bytes.fromhex(_digest(entry.sha256)))
    return digest.hexdigest()


def _file_entries(records: object, payloads: Mapping[str, bytes]) -> tuple[FileEntry, ...]:
    _require(type(records) is list and len(records) <= MAX_FILES, "FILE_COUNT")
    _require(isinstance(payloads, Mapping), "PAYLOAD_MAPPING")
    entries = []
    seen = set()
    upper_seen = set()
    for record in records:
        record = _shape(record, {"path", "size", "sha256"})
        path = validate_snapshot_path(record["path"])
        folded = path.casefold()
        _require(folded not in seen and path.upper() not in upper_seen, "PATH_COLLISION")
        seen.add(folded)
        upper_seen.add(path.upper())
        size = _integer(record["size"], 0, MAX_FILE)
        digest = _digest(record["sha256"])
        entries.append(FileEntry(path, size, digest))
    _require(set(payloads) == {f.path for f in entries}, "PAYLOAD_REFERENCES")
    # A file cannot also be another entry's parent directory.
    for paths in (seen, upper_seen):
        for path in paths:
            parts = path.split("/")
            _require(not any("/".join(parts[:i]) in paths for i in range(1, len(parts))), "PATH_PARENT_COLLISION")
    _require(sum(f.size for f in entries) <= MAX_TOTAL, "TOTAL_BYTES")
    for entry in entries:
        data = payloads.get(entry.path)
        _require(type(data) is bytes and len(data) == entry.size, "FILE_BYTES")
        _require(sha256(data) == entry.sha256, "FILE_HASH")
    return tuple(entries)


def validate_request(
    raw: bytes, *, manifest_sha256: str, payloads: Mapping[str, bytes], now: datetime,
) -> ValidatedRequest:
    """Validate exact manifest and file bytes. `now` must be supplied by the host.

    Registry membership, live leases and approval of image/policy/tool IDs are not
    inferable from these bytes and remain responsibilities of later broker slices.
    """
    request = _shape(_load(raw, MAX_MANIFEST, manifest_sha256), REQUEST_FIELDS)
    _require(request["schema"] == "aico.sandbox.request.v1", "REQUEST_VERSION")
    repo = _text(request["repository_id"], 201)
    _require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repo) is not None, "REPOSITORY_ID")
    _require(re.fullmatch(r"AICO-[0-9]+", _text(request["task_id"])) is not None, "TASK_ID")
    for name in ("attempt_id", "execution_id", "snapshot_id"):
        _uuid(request[name])
    _require(request["phase"] in ("REPRODUCTION", "HYPOTHESIS", "VERIFICATION", "POST_FIX_REPLAY"), "PHASE")
    _require(type(now) is datetime and now.utcoffset() is not None, "HOST_TIME")
    _require(_utc(request["created_utc"]) <= now < _utc(request["expires_utc"]), "REQUEST_TIME")
    for name in ("authorization_fingerprint", "scope_fingerprint", "dependencies_fingerprint",
                 "snapshot_root_sha256", "image_sha256", "supervisor_sha256",
                 "dependency_inventory_sha256", "policy_sha256"):
        _digest(request[name])
    _require(type(request["base_sha"]) is str and re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", request["base_sha"]) is not None, "BASE_SHA")
    for name in ("lease_binding_id", "worktree_registration_id", "image_id", "policy_id",
                 "compatibility_profile_id", "environment_profile_id"):
        _identifier(request[name])
    _require(request["network"] == "DENY", "NETWORK")
    _require(type(request["host_mounts"]) is list and not request["host_mounts"], "HOST_MOUNTS")
    limits = _shape(request["limits"], {"memory_mib", "vcpus", "scratch_mib", "processes", "execution_seconds", "output_bytes"})
    for name, maximum in (("memory_mib", 4096), ("vcpus", 2), ("scratch_mib", 8192),
                          ("processes", 128), ("execution_seconds", 900), ("output_bytes", MAX_OUTPUT)):
        _integer(limits[name], 1, maximum)
    files = _file_entries(request["files"], payloads)
    _require(_integer(request["file_count"], 0, MAX_FILES) == len(files), "FILE_COUNT")
    _require(_integer(request["total_bytes"], 0, MAX_TOTAL) == sum(f.size for f in files), "TOTAL_BYTES")
    _require(snapshot_root(files) == request["snapshot_root_sha256"], "SNAPSHOT_HASH")
    records = request["commands"]
    _require(type(records) is list and 1 <= len(records) <= MAX_COMMANDS, "COMMAND_COUNT")
    commands = []
    seen = set()
    for record in records:
        c = _shape(record, {"command_id", "tool_id", "argv", "cwd", "timeout_seconds"})
        cid = _identifier(c["command_id"])
        _require(cid not in seen, "COMMAND_COLLISION")
        seen.add(cid)
        tool = _identifier(c["tool_id"])
        argv = c["argv"]
        _require(type(argv) is list and len(argv) <= 128, "ARGUMENT_COUNT")
        args = tuple(_text(arg, 32768, allow_empty=True) for arg in argv)
        _require(sum(len(arg.encode("utf-8")) for arg in args) <= 32768, "ARGUMENT_BYTES")
        cwd = c["cwd"]
        if cwd != ".":
            cwd = validate_path(cwd)
            _require(any(f.path.startswith(cwd + "/") for f in files), "CWD_REFERENCE")
        timeout = _integer(c["timeout_seconds"], 1, 300)
        _require(timeout <= limits["execution_seconds"], "COMMAND_TIMEOUT")
        commands.append(Command(cid, tool, args, cwd, timeout))
    return ValidatedRequest(
        raw, manifest_sha256, repo, request["task_id"], request["attempt_id"],
        request["execution_id"], request["snapshot_id"], request["snapshot_root_sha256"],
        request["image_sha256"], request["policy_sha256"], files, tuple(commands), limits["output_bytes"],
    )


def validate_receipt(
    raw: bytes, *, receipt_sha256: str, request: ValidatedRequest,
    outputs: Mapping[str, bytes], cleanup_receipt_sha256: str,
) -> ValidatedReceipt:
    """Validate a sealed receipt against an already validated request and outputs.

    `cleanup_receipt_sha256` must come independently from the caller's trusted
    source. Equality cannot authenticate that source or prove cleanup happened.
    """
    _require(type(request) is ValidatedRequest, "REQUEST_REQUIRED")
    result = _shape(_load(raw, MAX_RECEIPT, receipt_sha256), RECEIPT_FIELDS)
    _require(result["schema"] == "aico.sandbox.receipt.v1", "RECEIPT_VERSION")
    expected = {
        "repository_id": request.repository_id, "task_id": request.task_id,
        "attempt_id": request.attempt_id, "execution_id": request.execution_id,
        "snapshot_id": request.snapshot_id, "request_sha256": request.manifest_sha256,
        "snapshot_root_sha256": request.snapshot_root_sha256,
        "image_sha256": request.image_sha256, "policy_sha256": request.policy_sha256,
    }
    _require(all(result[key] == value for key, value in expected.items()), "RECEIPT_BINDING")
    guest = _shape(result["guest_result"], {"commands", "source_integrity"})
    _require(guest["source_integrity"] in ("UNCHANGED", "CHANGED"), "SOURCE_INTEGRITY")
    observation = _shape(result["broker_observation"], {"termination", "cleanup", "cleanup_receipt_sha256"})
    _require(observation["termination"] in ("NORMAL", "FAILED", "CANCELLED", "TIMED_OUT", "INVALIDATED"), "TERMINATION")
    _require(observation["cleanup"] == "CONFIRMED", "CLEANUP_UNCONFIRMED")
    _require(_digest(observation["cleanup_receipt_sha256"]) == _digest(cleanup_receipt_sha256), "CLEANUP_BINDING")
    acceptance = result["acceptance"]
    _require(acceptance in ("ELIGIBLE_FOR_HOST_REVALIDATION", "REJECTED"), "ACCEPTANCE")
    records = guest["commands"]
    _require(type(records) is list and len(records) <= len(request.commands), "RESULT_COUNT")
    _require(isinstance(outputs, Mapping), "OUTPUT_MAPPING")
    eligible = acceptance == "ELIGIBLE_FOR_HOST_REVALIDATION"
    if eligible:
        _require(observation["termination"] == "NORMAL" and guest["source_integrity"] == "UNCHANGED", "RESULT_NOT_ELIGIBLE")
        _require(len(records) == len(request.commands), "RESULT_COUNT")
    total = 0
    keys = set()
    for index, record in enumerate(records):
        c = _shape(record, {"command_id", "exit_code", "stdout_sha256", "stderr_sha256", "stdout_bytes", "stderr_bytes", "output_complete"})
        _require(c["command_id"] == request.commands[index].command_id, "COMMAND_REFERENCE")
        _integer(c["exit_code"], -(2**31), 2**32 - 1)
        _require(type(c["output_complete"]) is bool, "OUTPUT_COMPLETE_TYPE")
        _require(not eligible or c["output_complete"], "OUTPUT_INCOMPLETE")
        combined = 0
        for stream in ("stdout", "stderr"):
            size = _integer(c[stream + "_bytes"], 0, MAX_COMMAND_OUTPUT)
            digest = _digest(c[stream + "_sha256"])
            key = c["command_id"] + "." + stream
            data = outputs.get(key)
            _require(type(data) is bytes and len(data) == size, "OUTPUT_BYTES")
            _require(sha256(data) == digest, "OUTPUT_HASH")
            keys.add(key)
            combined += size
        _require(combined <= MAX_COMMAND_OUTPUT, "COMMAND_OUTPUT_LIMIT")
        total += combined
    _require(total <= request.output_limit, "TOTAL_OUTPUT_LIMIT")
    _require(set(outputs) == keys, "OUTPUT_REFERENCES")
    return ValidatedReceipt(raw, receipt_sha256, request.execution_id, acceptance)
