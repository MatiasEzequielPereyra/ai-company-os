# Grounded Citation Spans v1

Project: AI Company OS
Revision: 1
Updated by: CODEX-ORCHESTRATOR
Authority: human authorization for bounded citations only; acceptance remains HOLD.
Base: a5c030cfb83bc98bc7d3d009df616cc7e3590cf0

## Audit and contract decision

The baseline validator requires the excerpt to equal complete normalized lines,
then limits it to 2048 UTF-8 bytes. The schema offers no substring locator.
Consequently a substantive 3405-byte line cannot be cited. Increasing the limit,
altering the source or silently truncating it would change evidence integrity.

Optional integer `byte_start` and `byte_end` locate a fragment within the selected
`start_line` through `end_line` range after existing normalization, joined with LF.
Offsets are zero-based and half-open: start inclusive, end exclusive. Line labels
are excluded. Both offsets must be present together. They must identify a nonempty
range on complete UTF-8 character boundaries. Strict decoding and ordinal exact
comparison validate the quoted bytes. No search for matching text is performed;
repeated occurrences remain distinguishable by their explicit position.

The opaque registered snapshot plus artifact ID binds task, path, raw SHA256 and
normalized SHA256. Caller-supplied path/hash/task overrides are rejected. Existing
live-source drift checks and process-local validation/publication receipts remain
required. Per-excerpt 2048-byte, aggregate 32768-byte, 16-line and three-reference
limits remain unchanged. Original sources remain intact.

## Schema compatibility

This is an additive extension of review-grounding-v1. Existing required fields
and whole-line semantics are unchanged. Omitting both offsets retains legacy
behavior. Older engines reject new offset fields because their schema is closed;
new span judgments require the updated runtime and schema together. No historical
judgment is reinterpreted. Optional primitive properties avoid canonical unions
unsupported by the Codex schema adapter. Its existing adapter strips nullable
optional placeholders before canonical validation. Semantic validation enforces
paired presence and UTF-8 byte constraints beyond JSON schema character limits.

The complete judgment already persists in the canonical .grounding.json sidecar;
no publication or lifecycle redesign is needed. A regression exercises real
publication and the permitted corrective transition in a disposable fixture.

## Relevance and coverage boundary

Each exact frozen obligation still requires its assessment, rationale and eligible
primary evidence for positive judgments. The prompt and schema now explicitly
require explaining how each fragment demonstrates that obligation; an irrelevant
quote is insufficient for SATISFIED. Missing support requires UNSATISFIED and
contradictory APPROVE remains rejected. Byte correspondence proves provenance,
not semantic relevance. The approved design and existing case S explicitly retain
this limitation; these tests do not prove a deterministic relevance classifier.
Guaranteeing rejection of every genuine irrelevant quote requires a separate
semantic architecture decision and cannot honestly be claimed from offsets.

## Regression coverage

The new PowerShell test covers legacy short lines, exact 3405-byte long lines,
beginning/middle/end fragments, bad bounds/types, UTF-8 split boundaries, wrong
content, missing paired offsets, over-limit legacy lines, wrong artifact/path/task
identities, forged hash fields, stale snapshots/live source hashes, duplicate text
at explicit positions, missing obligation coverage, contradictory approval,
empty positive evidence, forged validation/context, and sidecar roundtrip.
Five Python tests check schema compatibility, portability, limits and relevance
instructions. These deterministic fixtures make no real provider calls.

## Preserved boundaries

No changes to Run A engine/fixture/task state, historical evidence, CTO reports,
provider configuration, retry behavior, provider budgets, Run B or production TUI.
No provider execution or merge. The historical sixth maintenance check remains
a separate finding; this delivery does not claim historical 6/6 PASS or alter it.
