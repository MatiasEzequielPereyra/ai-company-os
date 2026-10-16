# Native sandbox data contracts: NATIVE-SBX-001

Project: AI Company OS
Revision: 2
Updated: 2026-10-16
Updated by: Codex implementer
Base: 5ce38da9281ddb4baaef4654a35cad447979f8a1

## Scope and authority

Sources: `NATIVE_SANDBOX_P0_CONTRACT_V1` and
`NATIVE_SANDBOX_P0_CONTRACT_AMENDMENT_V1`, supplied in the authorizing conversation.
The user's `NATIVE-SBX-001` instruction authorizes only isolated data validators
and pure synthetic tests. No commit, push, merge, runtime integration, VM, service,
provider call or writable enablement is authorized by this slice.

Implementation: `src/company_os/sandbox/contracts.py`, using the standard library
on Python >=3.11, consistent with the existing Python package. No new dependency.
Tests: `tests/test_native_sandbox_contracts.py`.

## Public validation API

- `validate_request(raw, *, manifest_sha256, payloads, now)` returns an immutable
  `ValidatedRequest`. `raw` and every payload must be `bytes`. `payloads` maps
  manifest-relative names to content supplied by the caller. `now` is an aware
  host datetime. No paths are opened. Every payload name must be referenced once.
- `validate_receipt(raw, *, receipt_sha256, request, outputs,
  cleanup_receipt_sha256)` returns an immutable `ValidatedReceipt`. `request`
  must be an already validated request. `outputs` maps `<command_id>.stdout` and
  `<command_id>.stderr` to bytes, including empty streams. The expected cleanup
  digest must be obtained independently by the caller.
- `validate_path` performs lexical Windows validation on any host OS.
- `sha256` hashes exact bytes; `snapshot_root` encodes the C1 binary transcript
  for `FileEntry` records (the latter is an encoding helper, not a substitute for
  request validation).
- All data rejections raise `ContractError` with a fixed code. Input values,
  source contents and paths are not echoed in errors.

The API never executes commands, discovers files or reads configuration. Its
immutable results contain tuples, frozen records and bytes, rather than the
caller's mutable input objects. There is no CLI or runtime entrypoint.

## Serialization and integrity

Documents must be UTF-8 without BOM, within their byte limit. Duplicate keys,
including escaped duplicates, are rejected at every level. Every object has an
exact required field set; unknown fields are rejected. No string/numeric/boolean
coercion is used. Nonfinite JSON constants and malformed Unicode are rejected.

Document digests cover the original bytes, not reserialized JSON. Reformatting
requires a new digest. SHA-256 strings are lowercase hexadecimal, length 64.
UUIDs are canonical lowercase, non-nil. Git base object IDs are lowercase
40 or 64 hexadecimal characters. Sandbox target tasks retain `AICO-<digits>`;
the engineering slice identifier `NATIVE-SBX-001` is not a target task receipt.
Timestamps require `yyyy-MM-ddTHH:mm:ssZ`; `created <= now < expires`.

Snapshot SHA-256 follows C1: sort by UTF-8 path bytes; concatenate big-endian
u32 path length, UTF-8 path, big-endian u64 size, raw 32-byte content digest.
Every file hash is recomputed from supplied content. Empty files/snapshots work.
Metadata totals are checked before payload hashing.

## Request profile

The required fields are defined by `REQUEST_FIELDS`. Nested files, commands and
limits have exact shapes. C1 constants are enforced: 8 MiB manifest, 20,000 files,
64 MiB per file, 1 GiB aggregate, 1..12 commands, 128 arguments and 32 KiB argument
content per command. Timeouts are 1..300 seconds and cannot exceed the requested
execution budget (at most 900 seconds).

Resource requests may narrow, never exceed V1 ceilings: 4096 MiB memory, 2 vCPU,
8192 MiB scratch, 128 processes, 16 MiB combined output. Network is `DENY` and
host mounts are empty. Identifiers are bounded ASCII tokens, not executable or
host paths. Tool/image/policy IDs are structurally checked, not approved here.

`cwd` is `.` or a safe directory represented by a file descendant in the
snapshot. Arguments are literal data; no shell interpretation or command-policy
authorization is attempted. Empty literal arguments are supported.

Windows names require NFC, `/` separators and <=180 UTF-16 code units. Reject
absolute/UNC/device/ADS/traversal/control paths, trailing dots/spaces, reserved
devices (including superscript COM/LPT digits), and `~` aliases. Reject exact,
casefold and uppercase-equivalent collisions and file/ancestor collisions.
The extra uppercase comparison conservatively covers dotless-I aliases.
The source-path safety check retains the existing writable policy's protected
prefixes and secret filename patterns. That check is not export authorization.

### Snapshot export policy (P1_SNAPSHOT_CONTROL_PLANE_EXCLUSION)

Every `files[].path` additionally passes `validate_snapshot_path`. Its fixed,
trusted V1 exclusions are separate from `validate_path`; manifests cannot grant
exceptions. No JSON fields, hash formats, identifiers or receipt contracts change.

- Reserved directory segments at any depth: Git/Codex/agent configuration,
  CI/editor/container/credential configuration, `scripts`, `tasks`, `docs`,
  `schemas`, `templates`, `acceptance` and `npm-bin` (exact list in
  `SNAPSHOT_RESERVED_DIRECTORIES`). Nested fixture copies are covered too.
- Reserved roots: governance/policies/broker/runtime/services/config and
  infrastructure/deployment/operations directories (exact list in
  `SNAPSHOT_RESERVED_ROOTS`). Product `src/app/config` remains admissible.
- Reserved names at any depth: AGENTS.md, SECURITY.md, CONTRIBUTING.md,
  CODEOWNERS, privileged tool/CI/deployment configuration and known SSH private
  key names (exact list in `SNAPSHOT_RESERVED_NAMES`).
- Matching uses uppercase followed by casefold to conservatively reject Windows
  aliases including dotless-I; lexical NFC and collision checks remain in place.
- Rejection code: `SNAPSHOT_EXPORT_FORBIDDEN`, or the pre-existing lexical,
  protected-path or secret-path code if that earlier check rejects the path.

This profile intentionally excludes whole reserved trees, including their product
examples or documentation. Ordinary product code/tests, package.json,
pyproject.toml and requirements.txt remain admissible subject to all other checks.
There is no exception mechanism in this slice. Any future exception must be
defined in a separately reviewed trusted host policy, never a request flag,
policy ID, fingerprint or embedded configuration file. Claimed policy metadata
does not select or weaken the fixed profile.

This is a conservative name-based exclusion policy, not proof that arbitrary
admissible bytes contain no secrets or control instructions. A future trusted
exporter must also classify project-specific control resources and inspect real
filesystem metadata; this validator neither discovers nor follows files.

## Receipt profile

The required fields are defined by `RECEIPT_FIELDS`. In addition to the C1
illustration, identity fields explicitly include repository, task, attempt and
snapshot IDs so no identity is inferred. They must equal the validated request.
Request, snapshot, image and policy hashes must also match.

Each command result requires `command_id`, integer `exit_code`,
`stdout_sha256`, `stderr_sha256`, `stdout_bytes`, `stderr_bytes` and boolean
`output_complete`. Results are an ordered prefix of requested commands, with
no duplicate, reordered or unrelated command IDs. Outputs must match their
declared byte sizes and hashes with no extra or missing streams.

Receipt JSON is limited to 1 MiB; stdout+stderr <=4 MiB per command; aggregate
output cannot exceed the request's <=16 MiB budget. Exit codes support signed
32-bit and unsigned Windows 32-bit values; booleans/floats are not integers.

Only sealed receipts with `cleanup: CONFIRMED` and a matching independently
supplied cleanup digest are validated. `ELIGIBLE_FOR_HOST_REVALIDATION` additionally
requires `termination: NORMAL`, `source_integrity: UNCHANGED`, all requested
commands and complete outputs. `REJECTED` supports a partial command prefix and
`FAILED`, `CANCELLED`, `TIMED_OUT`, or `INVALIDATED` termination. Nonzero exit is
valid data: diagnostics may require failure and this validator never declares
tests PASS. Unconfirmed cleanup remains outside a sealed valid receipt.

## Security limitations

These APIs establish data integrity and cross-document consistency, not trust.
A caller that supplies fabricated content and matching hashes can produce
consistent data. Broker identity, image/policy registries, signatures, live
authorization, leases, VSS/Git association, monitor freshness, actual cleanup,
symlinks/hardlinks/reparse metadata and the 240-unit absolute guest root bound
require future trusted components. Lexical validation cannot prove filesystem
object properties. Nothing here imports guest changes or enables execution.

Only this module's synthetic tests are run for the slice. Full product/runtime
suites, Hyper-V certification and adversarial host experiments are NOT_RUN.

## Skills and handoff

SKILLS_SELECTED: feature, code-review
SKILLS_APPLIED: feature implementation and local static review; no independent
review is claimed.
SKILL_SOURCES: .agents/skills/feature/SKILL.md;
.agents/skills/code-review/SKILL.md
SKILL_SELECTION_REASON: new data validation component with adversarial synthetic
tests and review of its strict parsing and security boundaries.

External independent review is required before any later integration. Existing
task/lifecycle/Review Grounding/authorization/lock/provider code is unchanged.
