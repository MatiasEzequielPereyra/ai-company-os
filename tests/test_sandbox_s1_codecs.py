"""Synthetic closed-shape fixtures and hostile codec inputs."""

import copy
import json
from datetime import datetime, timezone
import pytest
from company_os.sandbox.codecs import decode_piece, check_package_consistency
from company_os.sandbox.contracts import ContractError, sha256
from company_os.sandbox.puretypes import S1SyntheticLimits
from test_native_sandbox_contracts import (
    make_request,
    check_request,
    make_receipt,
    NOW,
    H,
)

LIMITS = S1SyntheticLimits(8388608, 33554432, 12, 256, 64, 256)
E = "44444444-4444-4444-8444-444444444444"


def encode(v):
    return json.dumps(v, separators=(",", ":")).encode()


def check(v, kind):
    b = encode(v)
    return decode_piece(b, expected_digest=sha256(b), kind=kind, limits=LIMITS)


def make_package(execution=True):
    req, payloads = make_request()
    parsed = check_request(req, payloads)
    identity = {
        k: req[k]
        for k in (
            "repository_id",
            "task_id",
            "attempt_id",
            "execution_id",
            "snapshot_id",
        )
    }
    pieces = {}
    audits = []

    def put(v):
        raw = encode(v)
        d = sha256(raw)
        pieces[d] = raw
        return {"sha256": d, "bytes": len(raw)}

    def audit(kind, phase, generation=0):
        raw = encode([kind, phase, generation])
        d = sha256(raw)
        pieces[d] = raw
        audits.append(
            {
                "kind": kind,
                "generation": generation,
                "phase": phase,
                "artifact": {"sha256": d, "bytes": len(raw)},
            }
        )
        return d

    clean = {
        "schema": "aico.sandbox.cleanup-evidence.v1",
        "identity": identity,
        "generation": 0,
        "scope": "FINAL_EXECUTION",
        "journal_epoch": E,
        "journal_sequence": 5,
        "started_tick": 1,
        "finished_tick": 2,
        "resources": [],
        "inventory_sha256": audit("RESOURCE_INVENTORY", "CLEANUP"),
        "journal_sha256": audit("RESOURCE_JOURNAL", "CLEANUP"),
        "cleanup_status": "CONFIRMED",
        "causes": [],
    }
    cr = put(clean)
    captures = {}
    for phase in ("INITIAL", "FINAL") if execution else ():
        witness = audit("WITNESS_TRANSCRIPT", phase)
        cap = {
            "schema": "aico.sandbox.capture-evidence.v1",
            "identity": identity,
            "generation": 0,
            "capture_phase": phase,
            "volume_id": "vol",
            "vss_snapshot_id": "vss-" + phase,
            "worktree_file_id": "wt",
            "gitdir_file_id": "git",
            "commondir_file_id": "common",
            "git_object_format": "sha1",
            "candidate_head_oid": req["base_sha"],
            "candidate_branch": "feature/synthetic",
            "index_sha256": H,
            "git_metadata_inventory_sha256": audit("GIT_INVENTORY", phase),
            "snapshot_root_sha256": req["snapshot_root_sha256"],
            "pre_witness_sha256": witness,
            "captured_witness_sha256": witness,
            "post_witness_sha256": witness,
            "journal_identity_and_coverage": {
                "journal_id": "j",
                "start_cursor": "a",
                "end_cursor": "b",
                "continuous": True,
                "range_sha256": H,
            },
            "coherence_result": "COHERENT",
        }
        captures[phase] = put(cap)
    mon = None
    if execution:
        mon = {
            "status": "COMPLETE",
            "first_sequence": 1,
            "last_sequence": 2,
            "observation_count": 2,
            "max_age_ns": 1,
            "max_evaluation_duration_ns": 1,
            "coverage": {
                "journal_id": "j",
                "start_cursor": "a",
                "end_cursor": "b",
                "continuous": True,
                "range_sha256": H,
            },
            "observations_sha256": audit("AUTHORITY_OBSERVATIONS", "AUTHORITY"),
            "invalidations_sha256": audit("INVALIDATIONS", "AUTHORITY"),
        }
    receipt = None
    outputs = {}
    if execution:
        rv, outputs = make_receipt(parsed)
        rv["broker_observation"]["cleanup_receipt_sha256"] = cr["sha256"]
        receipt = put(rv)
    rr = put(req)
    binding = {
        k: req[k]
        for k in (
            "authorization_fingerprint",
            "scope_fingerprint",
            "dependencies_fingerprint",
            "worktree_registration_id",
            "image_id",
            "image_sha256",
            "supervisor_sha256",
            "dependency_inventory_sha256",
            "policy_id",
            "policy_sha256",
            "compatibility_profile_id",
            "environment_profile_id",
        )
    }
    binding.update(binding_id=req["lease_binding_id"], principal_sid="S-1-5-21-1")
    host = {
        "schema": "aico.sandbox.host-evidence.v1",
        "identity": identity,
        "binding": binding,
        "request_sha256": rr["sha256"],
        "receipt_v1_sha256": receipt["sha256"] if receipt else None,
        "cleanup_sha256": cr["sha256"],
        "initial_capture_sha256": captures.get("INITIAL", {}).get("sha256"),
        "retry_capture_sha256": None,
        "final_capture_sha256": captures.get("FINAL", {}).get("sha256"),
        "lifecycle_at_seal": "SEALED",
        "execution_result": "COMPLETED" if execution else "FAILED",
        "resource_state": "CLEANUP_CONFIRMED",
        "terminal_outcome": "ACCEPTED" if execution else "FAILED",
        "started_untrusted_code": execution,
        "generation": 0,
        "retry_count": 0,
        "retry_resolution": None,
        "invalidation_latched": False,
        "causes": [],
        "monitor": mon,
        "journal_epoch": E,
        "seal_sequence": 8,
        "sealed_utc": "2026-10-15T12:01:00Z",
    }
    hr = put(host)
    package = {
        "schema": "aico.sandbox.receipt-package.v1",
        "package_kind": "EXECUTION_EVIDENCE" if execution else "HOST_TERMINAL",
        "provenance": "SIMULATION",
        "identity": identity,
        "broker_epoch": E,
        "seal_sequence": 8,
        "previous_package_sha256": None,
        "request": rr,
        "receipt_v1": receipt,
        "host_evidence": hr,
        "cleanup": cr,
        "initial_capture": captures.get("INITIAL"),
        "retry_capture": None,
        "final_capture": captures.get("FINAL"),
        "outputs": [
            {
                "command_id": k.rsplit(".", 1)[0],
                "stream": k.rsplit(".", 1)[1].upper(),
                "artifact": {"sha256": sha256(v), "bytes": len(v)},
            }
            for k, v in outputs.items()
        ],
        "audit_refs": audits,
        "evidence_policy_id": "synthetic",
        "evidence_policy_sha256": H,
    }
    return package, pieces, payloads, outputs


def package_check(p, pieces, payloads, outputs, limits=LIMITS):
    b = encode(p)
    return check_package_consistency(
        b,
        expected_digest=sha256(b),
        pieces=pieces,
        payloads=payloads,
        outputs=outputs,
        now=NOW,
        limits=limits,
    )


@pytest.mark.parametrize("execution", [True, False])
def test_valid_package(execution):
    report = package_check(*make_package(execution))
    assert (
        report.scope == "SIMULATION"
        and not report.operational
        and report.unauthenticated_audit
    )


@pytest.mark.parametrize(
    "kind", ["host-evidence", "cleanup-evidence", "capture-evidence", "receipt-package"]
)
def test_closed_shapes(kind):
    p, pieces, _, _ = make_package()
    v = (
        p
        if kind == "receipt-package"
        else next(
            json.loads(b)
            for b in pieces.values()
            if isinstance(json.loads(b), dict)
            and json.loads(b).get("schema") == "aico.sandbox." + kind + ".v1"
        )
    )
    assert check(v, kind).kind == kind
    v["unexpected"] = True
    with pytest.raises(ContractError):
        check(v, kind)


@pytest.mark.parametrize(
    "field", ["piece_bytes", "total_bytes", "depth", "items", "pieces", "events"]
)
@pytest.mark.parametrize("value", [0, -1, True, 1.1])
def test_limit_types(field, value):
    args = dict(
        piece_bytes=10000,
        total_bytes=100000,
        depth=12,
        items=256,
        pieces=64,
        events=256,
    )
    args[field] = value
    with pytest.raises(ContractError):
        S1SyntheticLimits(**args)


@pytest.mark.parametrize(
    "raw",
    [
        b'{"a":1,"a":2}',
        b'{"a":NaN}',
        b"\xef\xbb\xbf{}",
        b"\xff",
        b"{",
        b"[" * 13 + b"]" * 13,
    ],
)
def test_bad_json(raw):
    with pytest.raises(ContractError):
        decode_piece(raw, expected_digest=sha256(raw), kind="live-state", limits=LIMITS)


def test_owned_maps_and_unused_bytes():
    p, pcs, pl, o = make_package()

    class Bad(dict):
        def items(self):
            raise AssertionError("callback executed")

    with pytest.raises(ContractError, match="OWNED_MAPPING"):
        package_check(p, Bad(pcs), pl, o)
    pcs[H] = b"unused"
    with pytest.raises(ContractError):
        package_check(p, pcs, pl, o)


@pytest.mark.parametrize(
    "mutation", ["epoch", "missing", "audit", "duplicate", "cleanup", "output"]
)
def test_bindings(mutation):
    p, pcs, pl, o = make_package()
    if mutation == "epoch":
        p["broker_epoch"] = "55555555-5555-4555-8555-555555555555"
    if mutation == "missing":
        pcs.pop(p["request"]["sha256"])
    if mutation == "audit":
        p["audit_refs"] = []
    if mutation == "duplicate":
        p["audit_refs"].append(copy.deepcopy(p["audit_refs"][0]))
    if mutation == "cleanup":
        p["cleanup"]["sha256"] = H
    if mutation == "output":
        p["outputs"][0]["artifact"]["bytes"] += 1
    with pytest.raises(ContractError):
        package_check(p, pcs, pl, o)


def test_policy_and_auxiliaries():
    policy = {
        "policy_sha256": H,
        "approval_id": E,
        "approver_principal": "synthetic",
        "approved_utc": "2026-10-15T12:00:00Z",
        "scope": "EVIDENCE_POLICY",
        "revoked": False,
    }
    assert check(policy, "PolicyApproval").value["scope"] == "EVIDENCE_POLICY"
    p, *_ = make_package(False)
    identity = p["identity"]
    c = {
        "code": "PREFLIGHT_FAILED",
        "event_sequence": 1,
        "observed_tick": 0,
        "generation": 0,
    }
    rejection = {
        "schema": "aico.sandbox.rejection-record.v1",
        "identity": identity,
        "execution_started": False,
        "execution_result": "FAILED",
        "reason": c,
        "journal_epoch": E,
        "sequence": 1,
        "created_utc": "2026-10-15T12:00:00Z",
    }
    check(rejection, "rejection-record")
    live = {
        "schema": "aico.sandbox.live-state.v1",
        "identity": identity,
        "lifecycle_state": "REQUESTED",
        "execution_result": "PENDING",
        "resource_state": "NONE",
        "started_untrusted_code": False,
        "generation": 0,
        "retry_count": 0,
        "retry_resolution": None,
        "invalidation_latched": False,
        "causes": [],
        "journal_epoch": E,
        "version": 1,
    }
    check(live, "live-state")
    live["generation"] = True
    with pytest.raises(ContractError):
        check(live, "live-state")


def test_host_terminal_preserves_incoherent_capture():
    p, pcs, pl, o = make_package(True)
    host = json.loads(pcs.pop(p["host_evidence"]["sha256"]))
    cap = json.loads(pcs.pop(p["initial_capture"]["sha256"]))
    cap["coherence_result"] = "INCOHERENT"
    raw = encode(cap)
    cr = {"sha256": sha256(raw), "bytes": len(raw)}
    pcs[cr["sha256"]] = raw
    p["initial_capture"] = cr
    host["initial_capture_sha256"] = cr["sha256"]
    receipt = json.loads(pcs.pop(p["receipt_v1"]["sha256"]))
    receipt["acceptance"] = "REJECTED"
    receipt["broker_observation"]["termination"] = "FAILED"
    raw = encode(receipt)
    rr = {"sha256": sha256(raw), "bytes": len(raw)}
    pcs[rr["sha256"]] = raw
    p["receipt_v1"] = rr
    host["receipt_v1_sha256"] = rr["sha256"]
    host["execution_result"] = "FAILED"
    host["terminal_outcome"] = "FAILED"
    raw = encode(host)
    hr = {"sha256": sha256(raw), "bytes": len(raw)}
    pcs[hr["sha256"]] = raw
    p["host_evidence"] = hr
    p["package_kind"] = "HOST_TERMINAL"
    assert not package_check(p, pcs, pl, o).operational


def test_distinct_witness_members_are_not_ambiguous():
    p, pcs, pl, o = make_package()
    host = json.loads(pcs.pop(p["host_evidence"]["sha256"]))
    cap = json.loads(pcs.pop(p["initial_capture"]["sha256"]))
    for index, key in enumerate(("captured_witness_sha256", "post_witness_sha256")):
        raw = encode(["distinct witness", index])
        d = sha256(raw)
        pcs[d] = raw
        p["audit_refs"].append(
            {
                "kind": "WITNESS_TRANSCRIPT",
                "generation": 0,
                "phase": "INITIAL",
                "artifact": {"sha256": d, "bytes": len(raw)},
            }
        )
        cap[key] = d
    raw = encode(cap)
    cr = {"sha256": sha256(raw), "bytes": len(raw)}
    pcs[cr["sha256"]] = raw
    p["initial_capture"] = cr
    host["initial_capture_sha256"] = cr["sha256"]
    raw = encode(host)
    hr = {"sha256": sha256(raw), "bytes": len(raw)}
    pcs[hr["sha256"]] = raw
    p["host_evidence"] = hr
    assert package_check(p, pcs, pl, o).unauthenticated_audit


@pytest.mark.parametrize("sealed", ["2026-10-15T11:58:59Z", "2026-10-15T12:15:00Z"])
def test_execution_seal_requires_request_lifetime(sealed):
    p, pcs, pl, o = make_package()
    host = json.loads(pcs.pop(p["host_evidence"]["sha256"]))
    host["sealed_utc"] = sealed
    raw = encode(host)
    ref = {"sha256": sha256(raw), "bytes": len(raw)}
    pcs[ref["sha256"]] = raw
    p["host_evidence"] = ref
    with pytest.raises(ContractError, match="S1_SEAL_TIME"):
        package_check(p, pcs, pl, o)


def test_host_terminal_may_record_post_expiry_cleanup():
    p, pcs, pl, o = make_package(False)
    host = json.loads(pcs.pop(p["host_evidence"]["sha256"]))
    host["sealed_utc"] = "2026-10-15T13:00:00Z"
    raw = encode(host)
    ref = {"sha256": sha256(raw), "bytes": len(raw)}
    pcs[ref["sha256"]] = raw
    p["host_evidence"] = ref
    assert not package_check(p, pcs, pl, o).operational
