"""Bounded structural evidence codecs. No host authentication or effects."""

import json
import re
import unicodedata
from uuid import UUID
from datetime import datetime
from .contracts import (
    ContractError,
    sha256,
    validate_request,
    validate_receipt,
    validate_path,
)
from .puretypes import S1SyntheticLimits, DecodedPiece, ConsistencyReport, freeze

U64 = 2**64 - 1
from .model import CAUSE_CODES, validate_state_dimensions, validate_cause_result

LIFECYCLES = frozenset(
    "REQUESTED PREFLIGHT CAPTURING PREPARING READY RUNNING COLLECTING STOPPING DESTROYING CLEANUP_VERIFY REVALIDATING SEALED PUBLISHED REJECTED QUARANTINED RECOVERING".split()
)
RESULTS = frozenset("COMPLETED FAILED CANCELLED TIMED_OUT INVALIDATED".split())
RESOURCES = frozenset(
    "NONE PARTIAL_CREATION PREPARED POSSIBLY_ACTIVE POWER_OFF_CONFIRMED DESTRUCTION_PENDING CLEANUP_CONFIRMED QUARANTINED".split()
)


def need(ok, code="S1_SHAPE"):
    if not ok:
        raise ContractError(code)


def shape(v, fields):
    need(type(v) is dict and set(v) == set(fields.split()), "S1_FIELDS")
    return v


def text(v, n=256):
    need(type(v) is str, "S1_STRING")
    try:
        b = v.encode("utf-8")
    except UnicodeError:
        raise ContractError("S1_UNICODE") from None
    need(
        0 < len(b) <= n and not any(unicodedata.category(c).startswith("C") for c in v),
        "S1_STRING",
    )
    return v


def token(v, n=128):
    text(v, n)
    need(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", v) is not None, "S1_TOKEN")


def opaque(v, n=256):
    text(v, n)
    need(v.isascii(), "S1_OPAQUE")


def digest(v):
    need(type(v) is str and re.fullmatch("[0-9a-f]{64}", v) is not None, "S1_DIGEST")


def integer(v, lo=0, hi=U64):
    need(type(v) is int and lo <= v <= hi, "S1_INTEGER")


def boolean(v):
    need(type(v) is bool, "S1_BOOLEAN")


def enum(v, choices):
    need(type(v) is str and v in choices, "S1_ENUM")


def uuid(v):
    text(v, 36)
    try:
        parsed = UUID(v)
    except ValueError:
        raise ContractError("S1_UUID") from None
    need(str(parsed) == v and parsed.int != 0, "S1_UUID")


def utc(v):
    need(
        type(v) is str
        and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", v) is not None,
        "S1_UTC",
    )
    try:
        datetime.strptime(v, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        raise ContractError("S1_UTC") from None


def identity(v):
    shape(v, "repository_id task_id attempt_id execution_id snapshot_id")
    text(v["repository_id"], 201)
    need(
        re.fullmatch(
            r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", v["repository_id"]
        )
        is not None
    )
    need(
        type(v["task_id"]) is str
        and re.fullmatch(r"AICO-[0-9]+", v["task_id"]) is not None
    )
    for k in ("attempt_id", "execution_id", "snapshot_id"):
        uuid(v[k])


def ref(v):
    shape(v, "sha256 bytes")
    digest(v["sha256"])
    integer(v["bytes"])


def cause(v):
    shape(v, "code event_sequence observed_tick generation")
    enum(v["code"], CAUSE_CODES)
    integer(v["event_sequence"], 1)
    integer(v["observed_tick"])
    integer(v["generation"], 0, 1)


def causes(v):
    need(type(v) is list and len(v) <= 64)
    seen = set()
    for c in v:
        cause(c)
        need(c["event_sequence"] not in seen, "S1_DUPLICATE_CAUSE")
        seen.add(c["event_sequence"])


def retry(v, g, count, cs):
    integer(g, 0, 1)
    integer(count, 0, 1)
    need(g == count, "S1_GENERATION")
    if count == 0:
        need(v is None, "S1_RETRY")
        return
    shape(
        v,
        "cause_event_sequence retry_commit_sequence from_generation to_generation request_sha256",
    )
    integer(v["cause_event_sequence"], 1)
    integer(v["retry_commit_sequence"], v["cause_event_sequence"] + 1)
    need(
        type(v["from_generation"]) is int
        and v["from_generation"] == 0
        and type(v["to_generation"]) is int
        and v["to_generation"] == 1,
        "S1_RETRY",
    )
    digest(v["request_sha256"])
    need(
        any(
            c["code"] == "PRE_RUN_TRANSPORT_FAILURE"
            and c["generation"] == 0
            and c["event_sequence"] == v["cause_event_sequence"]
            for c in cs
        ),
        "S1_RETRY_CAUSE",
    )


def coverage(v):
    shape(v, "journal_id start_cursor end_cursor continuous range_sha256")
    opaque(v["journal_id"])
    opaque(v["start_cursor"], 128)
    opaque(v["end_cursor"], 128)
    boolean(v["continuous"])
    digest(v["range_sha256"])


def binding(v):
    shape(
        v,
        "binding_id principal_sid authorization_fingerprint scope_fingerprint dependencies_fingerprint worktree_registration_id image_id image_sha256 supervisor_sha256 dependency_inventory_sha256 policy_id policy_sha256 compatibility_profile_id environment_profile_id",
    )
    for k, x in v.items():
        if k.endswith("sha256") or k.endswith("fingerprint"):
            digest(x)
        elif k == "principal_sid":
            text(x)
            need(
                re.fullmatch(r"S-1-(?:0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*)){1,15}", x)
                is not None,
                "S1_SID",
            )
        else:
            token(x)


def monitor(v):
    shape(
        v,
        "status first_sequence last_sequence observation_count max_age_ns max_evaluation_duration_ns coverage observations_sha256 invalidations_sha256",
    )
    enum(v["status"], ("COMPLETE", "UNPROVEN"))
    for k in (
        "first_sequence",
        "last_sequence",
        "max_age_ns",
        "max_evaluation_duration_ns",
    ):
        integer(v[k])
    integer(v["observation_count"], 0, 2**32 - 1)
    need(v["last_sequence"] >= v["first_sequence"])
    coverage(v["coverage"])
    digest(v["observations_sha256"])
    digest(v["invalidations_sha256"])
    if v["status"] == "COMPLETE":
        need(
            v["coverage"]["continuous"]
            and v["observation_count"] > 0
            and v["first_sequence"] > 0
            and v["observation_count"] == v["last_sequence"] - v["first_sequence"] + 1
            and v["max_age_ns"] <= 3_000_000_000
            and v["max_evaluation_duration_ns"] <= 1_000_000_000,
            "S1_MONITOR",
        )


def resource(v):
    shape(
        v,
        "resource_operation_id resource_type expected_parent_id reserved_relative_name ownership_nonce actual_id existence ownership disposition observation_sha256",
    )
    uuid(v["resource_operation_id"])
    uuid(v["ownership_nonce"])
    enum(
        v["resource_type"],
        "VM VM_CONFIGURATION DIFFERENCING_DISK TEMP_DIRECTORY VSS CHANNEL AUXILIARY_PROCESS".split(),
    )
    for k in ("expected_parent_id", "actual_id"):
        if v[k] is not None:
            opaque(v[k], 512)
    validate_path(v["reserved_relative_name"])
    need(len(v["reserved_relative_name"].encode("utf-16-le")) // 2 <= 180)
    enum(v["existence"], ("ABSENT", "PRESENT", "UNKNOWN"))
    enum(v["ownership"], ("OWNED", "NOT_OWNED", "AMBIGUOUS"))
    enum(v["disposition"], ("NOT_CREATED", "REMOVED", "PENDING", "UNPROVEN"))
    digest(v["observation_sha256"])


FIELDS = {
    "capture-evidence": "schema identity generation capture_phase volume_id vss_snapshot_id worktree_file_id gitdir_file_id commondir_file_id git_object_format candidate_head_oid candidate_branch index_sha256 git_metadata_inventory_sha256 snapshot_root_sha256 pre_witness_sha256 captured_witness_sha256 post_witness_sha256 journal_identity_and_coverage coherence_result",
    "cleanup-evidence": "schema identity generation scope journal_epoch journal_sequence started_tick finished_tick resources inventory_sha256 journal_sha256 cleanup_status causes",
    "host-evidence": "schema identity binding request_sha256 receipt_v1_sha256 cleanup_sha256 initial_capture_sha256 retry_capture_sha256 final_capture_sha256 lifecycle_at_seal execution_result resource_state terminal_outcome started_untrusted_code generation retry_count retry_resolution invalidation_latched causes monitor journal_epoch seal_sequence sealed_utc",
    "receipt-package": "schema package_kind provenance identity broker_epoch seal_sequence previous_package_sha256 request receipt_v1 host_evidence cleanup initial_capture retry_capture final_capture outputs audit_refs evidence_policy_id evidence_policy_sha256",
    "rejection-record": "schema identity execution_started execution_result reason journal_epoch sequence created_utc",
    "live-state": "schema identity lifecycle_state execution_result resource_state started_untrusted_code generation retry_count retry_resolution invalidation_latched causes journal_epoch version",
    "PolicyApproval": "policy_sha256 approval_id approver_principal approved_utc scope revoked",
}


def validate(v, kind):
    shape(v, FIELDS[kind])
    if kind == "PolicyApproval":
        digest(v["policy_sha256"])
        uuid(v["approval_id"])
        text(v["approver_principal"])
        utc(v["approved_utc"])
        need(v["scope"] == "EVIDENCE_POLICY")
        boolean(v["revoked"])
        return
    need(v["schema"] == "aico.sandbox." + kind + ".v1", "S1_VERSION")
    identity(v["identity"])
    if kind == "capture-evidence":
        integer(v["generation"], 0, 1)
        enum(v["capture_phase"], ("INITIAL", "RETRY", "FINAL"))
        for k in (
            "volume_id",
            "vss_snapshot_id",
            "worktree_file_id",
            "gitdir_file_id",
            "commondir_file_id",
        ):
            opaque(v[k])
        enum(v["git_object_format"], ("sha1", "sha256"))
        need(
            type(v["candidate_head_oid"]) is str
            and re.fullmatch(
                "[0-9a-f]{"
                + ("40" if v["git_object_format"] == "sha1" else "64")
                + "}",
                v["candidate_head_oid"],
            )
            is not None
        )
        text(v["candidate_branch"], 1024)
        need(
            unicodedata.normalize("NFC", v["candidate_branch"]) == v["candidate_branch"]
        )
        for k in (
            "index_sha256",
            "git_metadata_inventory_sha256",
            "snapshot_root_sha256",
            "pre_witness_sha256",
            "captured_witness_sha256",
            "post_witness_sha256",
        ):
            digest(v[k])
        coverage(v["journal_identity_and_coverage"])
        enum(v["coherence_result"], ("COHERENT", "INCOHERENT", "UNPROVEN"))
    elif kind == "cleanup-evidence":
        integer(v["generation"], 0, 1)
        enum(v["scope"], ("GENERATION", "FINAL_EXECUTION"))
        uuid(v["journal_epoch"])
        integer(v["journal_sequence"], 1)
        integer(v["started_tick"])
        integer(v["finished_tick"], v["started_tick"])
        digest(v["inventory_sha256"])
        digest(v["journal_sha256"])
        enum(v["cleanup_status"], ("CONFIRMED", "UNPROVEN"))
        causes(v["causes"])
        need(type(v["resources"]) is list and len(v["resources"]) <= 256)
        seen = set()
        for r in v["resources"]:
            resource(r)
            need(r["resource_operation_id"] not in seen, "S1_RESOURCE_DUPLICATE")
            seen.add(r["resource_operation_id"])
        if v["cleanup_status"] == "CONFIRMED":
            need(
                all(
                    r["existence"] == "ABSENT"
                    and r["ownership"] == "OWNED"
                    and r["disposition"] in ("NOT_CREATED", "REMOVED")
                    for r in v["resources"]
                ),
                "S1_CLEANUP",
            )
    elif kind in ("host-evidence", "live-state"):
        causes(v["causes"])
        retry(v["retry_resolution"], v["generation"], v["retry_count"], v["causes"])
        boolean(v["invalidation_latched"])
        boolean(v["started_untrusted_code"])
        uuid(v["journal_epoch"])
        enum(
            v["execution_result"],
            RESULTS | ({"PENDING"} if kind == "live-state" else set()),
        )
        enum(v["resource_state"], RESOURCES)
        validate_state_dimensions(
            v["lifecycle_at_seal"] if kind == "host-evidence" else v["lifecycle_state"],
            v["execution_result"],
            v["resource_state"],
            v["started_untrusted_code"],
            v["invalidation_latched"],
        )
        need(
            v["invalidation_latched"] == (v["execution_result"] == "INVALIDATED"),
            "S1_LATCH",
        )
        need(
            all(c["generation"] <= v["generation"] for c in v["causes"]),
            "S1_CAUSE_BINDING",
        )
        resolution = v["retry_resolution"]
        validate_cause_result(
            v["execution_result"],
            v["generation"],
            resolution["cause_event_sequence"] if resolution is not None else None,
            tuple(
                (c["code"], c["generation"], c["event_sequence"]) for c in v["causes"]
            ),
        )
        if kind == "host-evidence":
            integer(v["seal_sequence"], 1)
            need(
                all(c["event_sequence"] <= v["seal_sequence"] for c in v["causes"]),
                "S1_CAUSE_BINDING",
            )
            if resolution is not None:
                need(
                    resolution["retry_commit_sequence"] <= v["seal_sequence"],
                    "S1_RETRY",
                )
            binding(v["binding"])
            need(
                v["lifecycle_at_seal"] == "SEALED"
                and v["resource_state"] == "CLEANUP_CONFIRMED"
            )
            enum(
                v["terminal_outcome"],
                ("ACCEPTED", "FAILED", "CANCELLED", "TIMED_OUT", "INVALIDATED"),
            )
            need(
                v["terminal_outcome"]
                == (
                    "ACCEPTED"
                    if v["execution_result"] == "COMPLETED"
                    else v["execution_result"]
                ),
                "S1_TERMINAL",
            )
            for k in ("request_sha256", "cleanup_sha256"):
                digest(v[k])
            for k in (
                "receipt_v1_sha256",
                "initial_capture_sha256",
                "retry_capture_sha256",
                "final_capture_sha256",
            ):
                if v[k] is not None:
                    digest(v[k])
            integer(v["seal_sequence"], 1)
            utc(v["sealed_utc"])
            if v["monitor"] is not None:
                monitor(v["monitor"])
        else:
            enum(v["lifecycle_state"], LIFECYCLES)
            integer(v["version"], 1)
            if v["lifecycle_state"] in ("SEALED", "PUBLISHED"):
                need(
                    v["execution_result"] != "PENDING"
                    and v["resource_state"] == "CLEANUP_CONFIRMED"
                )
            if v["lifecycle_state"] == "REJECTED":
                need(
                    not v["started_untrusted_code"]
                    and v["resource_state"] == "NONE"
                    and v["execution_result"] != "PENDING"
                )
    elif kind == "receipt-package":
        enum(v["package_kind"], ("EXECUTION_EVIDENCE", "HOST_TERMINAL"))
        enum(v["provenance"], ("OPERATIONAL", "SIMULATION"))
        uuid(v["broker_epoch"])
        integer(v["seal_sequence"], 1)
        if v["previous_package_sha256"] is not None:
            digest(v["previous_package_sha256"])
        for k in ("request", "host_evidence", "cleanup"):
            ref(v[k])
        for k in ("receipt_v1", "initial_capture", "retry_capture", "final_capture"):
            if v[k] is not None:
                ref(v[k])
        token(v["evidence_policy_id"])
        digest(v["evidence_policy_sha256"])
        need(type(v["outputs"]) is list and len(v["outputs"]) <= 24)
        seen = set()
        for r in v["outputs"]:
            shape(r, "command_id stream artifact")
            token(r["command_id"])
            enum(r["stream"], ("STDOUT", "STDERR"))
            ref(r["artifact"])
            key = (r["command_id"], r["stream"])
            need(key not in seen, "S1_OUTPUT_DUPLICATE")
            seen.add(key)
        need(type(v["audit_refs"]) is list and len(v["audit_refs"]) <= 32)
        seen = set()
        for r in v["audit_refs"]:
            shape(r, "kind generation phase artifact")
            enum(
                r["kind"],
                "RESOURCE_INVENTORY RESOURCE_JOURNAL AUTHORITY_OBSERVATIONS INVALIDATIONS GIT_INVENTORY WITNESS_TRANSCRIPT".split(),
            )
            integer(r["generation"], 0, 1)
            enum(r["phase"], ("INITIAL", "RETRY", "FINAL", "CLEANUP", "AUTHORITY"))
            ref(r["artifact"])
            key = (
                r["kind"],
                r["generation"],
                r["phase"],
                r["artifact"]["sha256"] if r["kind"] == "WITNESS_TRANSCRIPT" else None,
            )
            need(key not in seen, "S1_AUDIT_DUPLICATE")
            seen.add(key)
    elif kind == "rejection-record":
        need(type(v["execution_started"]) is bool and not v["execution_started"])
        enum(v["execution_result"], RESULTS - {"COMPLETED"})
        cause(v["reason"])
        uuid(v["journal_epoch"])
        integer(v["sequence"], 1)
        utc(v["created_utc"])


def validate_limits(limits):
    need(type(limits) is S1SyntheticLimits, "S1_LIMIT_CONFIGURATION")
    S1SyntheticLimits.__post_init__(limits)


def load(raw, dig, limits):
    validate_limits(limits)
    need(type(limits) is S1SyntheticLimits, "S1_LIMIT_CONFIGURATION")
    need(
        type(raw) is bytes
        and 0 < len(raw) <= min(limits.piece_bytes, limits.total_bytes),
        "S1_BYTES",
    )
    digest(dig)
    need(sha256(raw) == dig, "S1_HASH")
    need(not raw.startswith(b"\xef\xbb\xbf"), "S1_BOM")
    depth = 0
    quoted = False
    escaped = False
    for c in raw:
        if quoted:
            if escaped:
                escaped = False
            elif c == 92:
                escaped = True
            elif c == 34:
                quoted = False
        elif c == 34:
            quoted = True
        elif c in (91, 123):
            depth += 1
            need(depth <= limits.depth, "S1_DEPTH")
        elif c in (93, 125):
            depth -= 1
            need(depth >= 0, "S1_JSON")

    def pairs(ps):
        d = {}
        for k, v in ps:
            need(k not in d, "S1_DUPLICATE_KEY")
            d[k] = v
        return d

    def bad(_):
        raise ContractError("S1_NONFINITE")

    def bounded_integer(value):
        # S1 integers are bounded by U64. Reject before int() so this never
        # depends on the interpreter's process-wide digit-limit configuration.
        need(len(value.lstrip("-")) <= 20, "S1_INTEGER")
        return int(value)

    try:
        obj = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=pairs,
            parse_constant=bad,
            parse_int=bounded_integer,
        )
    except (UnicodeError, json.JSONDecodeError, RecursionError):
        raise ContractError("S1_JSON") from None

    def walk(v):
        if type(v) in (dict, list):
            need(len(v) <= limits.items, "S1_ITEMS")
            for x in (v.values() if type(v) is dict else v):
                walk(x)
        elif type(v) is str:
            try:
                v.encode("utf-8")
            except UnicodeError:
                raise ContractError("S1_UNICODE") from None

    walk(obj)
    return obj


def decode_piece(raw, *, expected_digest, kind, limits):
    need(type(kind) is str and kind in FIELDS, "S1_KIND")
    v = load(raw, expected_digest, limits)
    validate(v, kind)
    return DecodedPiece(raw, expected_digest, kind, freeze(v))


def check_package_consistency(
    raw, *, expected_digest, pieces, payloads, outputs, now, limits
):
    validate_limits(limits)
    need(type(raw) is bytes, "S1_BYTES")
    total = len(raw)
    for mapping in (pieces, payloads, outputs):
        need(type(mapping) is dict, "S1_OWNED_MAPPING")
        need(len(mapping) <= limits.pieces, "S1_PIECE_COUNT")
        for k, v in mapping.items():
            need(type(k) is str and type(v) is bytes, "S1_OWNED_MAPPING")
            need(len(v) <= limits.piece_bytes, "S1_BYTES")
            total += len(v)
    need(total <= limits.total_bytes, "S1_TOTAL_BYTES")
    pieces = dict(pieces)
    payloads = dict(payloads)
    outputs = dict(outputs)
    p = load(raw, expected_digest, limits)
    validate(p, "receipt-package")
    used = set()
    audit_used = set()

    def resolve(r, kind):
        ref(r)
        d = r["sha256"]
        need(d in pieces, "S1_MISSING_REF")
        b = pieces[d]
        need(len(b) == r["bytes"] and sha256(b) == d, "S1_REF_BYTES")
        used.add(d)
        v = load(b, d, limits)
        if kind not in ("request", "receipt"):
            validate(v, kind)
        return v, b, d

    request, request_raw, request_hash = resolve(p["request"], "request")
    validated = validate_request(
        request_raw, manifest_sha256=request_hash, payloads=payloads, now=now
    )
    host, _, _ = resolve(p["host_evidence"], "host-evidence")
    cleanup, _, cleanup_hash = resolve(p["cleanup"], "cleanup-evidence")
    ident = p["identity"]
    need(all(request[k] == ident[k] for k in ident), "S1_IDENTITY")
    for v in (host, cleanup):
        need(v["identity"] == ident, "S1_IDENTITY")
    need(
        host["request_sha256"] == request_hash
        and host["cleanup_sha256"] == cleanup_hash,
        "S1_BINDING",
    )
    need(
        host["journal_epoch"] == p["broker_epoch"] == cleanup["journal_epoch"]
        and host["seal_sequence"] == p["seal_sequence"]
        and cleanup["journal_sequence"] <= host["seal_sequence"],
        "S1_EPOCH_SEQUENCE",
    )
    need(
        cleanup["scope"] == "FINAL_EXECUTION"
        and cleanup["cleanup_status"] == "CONFIRMED"
        and cleanup["generation"] == host["generation"],
        "S1_CLEANUP",
    )
    need(cleanup["finished_tick"] >= cleanup["started_tick"], "S1_CLEANUP")
    bind = host["binding"]
    for k in bind:
        if k == "principal_sid":
            continue
        rk = "lease_binding_id" if k == "binding_id" else k
        need(bind[k] == request[rk], "S1_BINDING")
    captures = {}
    for field, phase in (
        ("initial_capture", "INITIAL"),
        ("retry_capture", "RETRY"),
        ("final_capture", "FINAL"),
    ):
        r = p[field]
        hd = host[field + "_sha256"]
        need((r is None) == (hd is None), "S1_CAPTURE_BINDING")
        if r is not None:
            cap, _, d = resolve(r, "capture-evidence")
            need(
                d == hd and cap["identity"] == ident and cap["capture_phase"] == phase,
                "S1_CAPTURE_BINDING",
            )
            need(
                cap["generation"] == (0 if phase == "INITIAL" else host["generation"]),
                "S1_GENERATION",
            )
            need(
                cap["snapshot_root_sha256"] == request["snapshot_root_sha256"]
                and cap["candidate_head_oid"] == request["base_sha"],
                "S1_CAPTURE_SOURCE",
            )
            captures[phase] = cap
    if host["generation"] == 0:
        need(p["retry_capture"] is None, "S1_RETRY")
    if host["retry_resolution"] is not None:
        need(host["retry_resolution"]["request_sha256"] == request_hash, "S1_RETRY")
    receipt = None
    if p["receipt_v1"] is not None:
        receipt, receipt_raw, d = resolve(p["receipt_v1"], "receipt")
        need(host["receipt_v1_sha256"] == d, "S1_RECEIPT_BINDING")
        validate_receipt(
            receipt_raw,
            receipt_sha256=d,
            request=validated,
            outputs=outputs,
            cleanup_receipt_sha256=cleanup_hash,
        )
    else:
        need(
            host["receipt_v1_sha256"] is None and not outputs and not p["outputs"],
            "S1_RECEIPT_BINDING",
        )
    expected_outputs = {}
    if receipt is not None:
        for c in receipt["guest_result"]["commands"]:
            for stream in ("stdout", "stderr"):
                expected_outputs[(c["command_id"], stream.upper())] = (
                    c[stream + "_sha256"],
                    c[stream + "_bytes"],
                )
    need(len(expected_outputs) == len(p["outputs"]), "S1_OUTPUT_BINDING")
    for o in p["outputs"]:
        need(
            expected_outputs.get((o["command_id"], o["stream"]))
            == (o["artifact"]["sha256"], o["artifact"]["bytes"]),
            "S1_OUTPUT_BINDING",
        )
    # Opaque audit bytes are membership/digest checked, never authenticated facts.
    audits = {}
    for a in p["audit_refs"]:
        r = a["artifact"]
        d = r["sha256"]
        need(d in pieces, "S1_MISSING_AUDIT")
        b = pieces[d]
        need(len(b) == r["bytes"] and sha256(b) == d, "S1_AUDIT_HASH")
        used.add(d)
        audit_used.add(d)
        audits[(a["kind"], a["generation"], a["phase"])] = d
    g = host["generation"]

    def audit(kind, generation, phase, d):
        need(audits.get((kind, generation, phase)) == d, "S1_AUDIT_BINDING")

    audit("RESOURCE_INVENTORY", g, "CLEANUP", cleanup["inventory_sha256"])
    audit("RESOURCE_JOURNAL", g, "CLEANUP", cleanup["journal_sha256"])
    m = host["monitor"]
    if m is not None:
        audit("AUTHORITY_OBSERVATIONS", g, "AUTHORITY", m["observations_sha256"])
        audit("INVALIDATIONS", g, "AUTHORITY", m["invalidations_sha256"])
        need(m["last_sequence"] <= host["seal_sequence"], "S1_MONITOR_SEQUENCE")
    for phase, cap in captures.items():
        generation = cap["generation"]
        audit("GIT_INVENTORY", generation, phase, cap["git_metadata_inventory_sha256"])
        # A single witness transcript binds all three witness digests by membership.
        witness_digests = {
            a["artifact"]["sha256"]
            for a in p["audit_refs"]
            if a["kind"] == "WITNESS_TRANSCRIPT"
            and a["generation"] == generation
            and a["phase"] == phase
        }
        need(
            {
                cap["pre_witness_sha256"],
                cap["captured_witness_sha256"],
                cap["post_witness_sha256"],
            }
            <= witness_digests,
            "S1_WITNESS_BINDING",
        )
    if p["package_kind"] == "EXECUTION_EVIDENCE":
        need(
            request["created_utc"] <= host["sealed_utc"] < request["expires_utc"],
            "S1_SEAL_TIME",
        )
        need(
            receipt is not None
            and host["started_untrusted_code"]
            and host["execution_result"] == "COMPLETED"
            and host["terminal_outcome"] == "ACCEPTED"
            and not host["invalidation_latched"],
            "S1_EXECUTION_DISCRIMINANT",
        )
        need(
            "INITIAL" in captures
            and "FINAL" in captures
            and (g == 0 or "RETRY" in captures),
            "S1_EXECUTION_CAPTURE",
        )
        need(
            all(
                cap["coherence_result"] == "COHERENT"
                and cap["journal_identity_and_coverage"]["continuous"]
                for cap in captures.values()
            ),
            "S1_CAPTURE_COHERENCE",
        )
        need(m is not None and m["status"] == "COMPLETE", "S1_MONITOR")
        need(
            receipt["acceptance"] == "ELIGIBLE_FOR_HOST_REVALIDATION",
            "S1_RECEIPT_ACCEPTANCE",
        )
    else:
        need(host["terminal_outcome"] != "ACCEPTED", "S1_HOST_TERMINAL")
        if receipt is not None:
            need(receipt["acceptance"] == "REJECTED", "S1_RECEIPT_ACCEPTANCE")
    need(set(pieces) == used, "S1_UNUSED_PIECES")
    # Typed reference graph: package -> host -> captures/cleanup/receipt -> request.
    # Identity-binding above prevents redirected semantic edges; digest self-edges fail.
    graph = {
        expected_digest: {
            p[k]["sha256"]
            for k in (
                "request",
                "receipt_v1",
                "host_evidence",
                "cleanup",
                "initial_capture",
                "retry_capture",
                "final_capture",
            )
            if p[k] is not None
        }
    }
    graph[p["host_evidence"]["sha256"]] = {
        host[k]
        for k in (
            "request_sha256",
            "receipt_v1_sha256",
            "cleanup_sha256",
            "initial_capture_sha256",
            "retry_capture_sha256",
            "final_capture_sha256",
        )
        if host[k] is not None
    }
    if receipt is not None:
        graph[p["receipt_v1"]["sha256"]] = {request_hash, cleanup_hash}
    visiting = set()
    done = set()

    def visit(d):
        need(d not in visiting, "S1_REFERENCE_CYCLE")
        if d in done:
            return
        visiting.add(d)
        for child in graph.get(d, ()):
            visit(child)
        visiting.remove(d)
        done.add(d)

    visit(expected_digest)
    return ConsistencyReport(expected_digest, p["package_kind"], p["provenance"])
