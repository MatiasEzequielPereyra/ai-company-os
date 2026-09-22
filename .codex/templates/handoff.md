# Engineering Handoff

Follow [Durable Company State](../protocols/company-state.md). Publish at `docs/engineering/handoffs/<project>/<id>.md`; published handoffs are superseded by successors rather than overwritten.

## Durable Metadata

Project:

Handoff ID:

Revision:

Updated (UTC ISO 8601):

Updated by:

Previous handoff (path or NONE):

Git base commit (or UNKNOWN):

Initial receipt status: PENDING

## Recipient Receipt

After publication, write this section as a new `<id>-receipt-<sequence>.md` sibling; preserve the original delivery. Acceptance acknowledges context, not task completion, gate approval or execution permission.

Delivery path and SHA-256:

Previous receipt (path or NONE):

Status (PENDING / ACCEPTED / CHANGES_REQUESTED):

Recipient name/role:

Recorded at (UTC ISO 8601):

Rationale and requested corrections:

## Authorization Receipt

Requester and date/reference:

Request excerpt or faithful scope receipt:

Permitted actions:

Retained restrictions (including dry-run/read-only limits):

Superseded authorization and exact scope of change (or NONE):

## Source Manifest

Use repository-relative paths. Include exact SHA-256 content hashes for relevant sources, including uncommitted/untracked files. Exclude this handoff and subsequently refreshed derived indexes. Unknown values remain UNKNOWN.

| Source path | Revision | SHA-256 | Committed / modified / untracked |
| --- | --- | --- | --- |
| | | | |

## Task

{{TASK}}

## From

{{FROM}}

## To

{{TO}}

## Objective

{{OBJECTIVE}}

---

## Completed

- 

## Files Changed

- 

## APIs / Contracts

- 

## Database Changes

- 

## Tests

- 

## Important Decisions

- 

Decision IDs, status (accepted/proposed/pending), owner and canonical source:

## Known Issues

- 

## Blockers

- 

Blocking decision/task IDs, transitive impact, required resolution and escalation owner:

## Follow-Up Work

- 

Next owner:

Next permitted action and dependencies:

Ticket paths and explicit statuses (READY does not grant permission):

## Verification

Tests:

Lint:

Build:

Other checks:

Use NOT_RUN when no check ran. Link results and reviewed source revisions; distinguish planning validation from implementation tests.

Gate approvals (owner, outcome, evidence; NOT_APPLICABLE requires owner rationale):

Publication checks (all source links/IDs valid, hashes match, unresolved decisions retained):

Recovery notes (interrupted work, inconsistent/stale sources, local changes to preserve):
