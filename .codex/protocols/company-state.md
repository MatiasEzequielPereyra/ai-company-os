# Durable Company State

Use this protocol when recording planning, handing work to another role, or resuming a project without conversation history. Apply the existing [task lifecycle](task-lifecycle.md), [quality gates](../policies/quality-gates.md), and [definition of done](../policies/definition-of-done.md).

## Sources and ownership

- The project's README and explicit user decisions establish scope. Product documents in `docs/product/` record confirmed requirements and open product decisions; PM owns them.
- Architecture documents in `docs/architecture/` and accepted ADRs in `docs/decisions/` record technical decisions; CTO owns them. Proposals remain distinguishable from accepted decisions.
- Plans in `docs/engineering/` describe sequencing and dependencies; Engineering Manager (EM) owns coordination.
- Each ticket under `tasks/` owns its status, acceptance criteria, dependency IDs, blockers and evidence. Preserve existing IDs and paths. The explicit `Status` field is authoritative; a directory name is not a status and transitions require no directory move.
- `.codex/state/company-state.md`, `current-sprint.md`, and `blockers.md` are derived indexes linking to those sources. They do not resolve decisions, grant authorization, or override tickets.
- Durable handoffs live at `docs/engineering/handoffs/<project>/<id>.md`, using the [handoff template](../templates/handoff.md). Published handoffs are historical snapshots; publish a successor to correct or supersede one.

Record `Project`, monotonic document `Revision`, `Updated` (UTC ISO 8601), `Updated by`, and source links on operational records. Record source document revisions and SHA-256 hashes of exact content in handoffs, together with the Git base commit when available. Include uncommitted and untracked sources: a commit reference alone does not identify them. Use `UNKNOWN` for unavailable provenance, never invented values.

## Authorization and transitions

| Ticket status | Meaning |
| --- | --- |
| BACKLOG | Identified work whose preparation is incomplete. |
| READY | Owner, objective, acceptance criteria and context are recorded; required decisions and blocking dependencies are resolved. Execution still requires authorization. |
| ACTIVE | Assigned owner is performing authorized work, including documentation when that is the task scope. |
| REVIEW | Work and local verification evidence are submitted for the assigned review. |
| QA | Review passed; applicable acceptance criteria are being verified. |
| SECURITY | Applicable security validation is pending or underway. |
| BLOCKED | An unresolved decision, dependency or condition prevents progress; reason, impact and escalation owner are recorded. |
| DONE | Original task objective and all applicable gates are satisfied, with CEO final verification recorded. |

Ticket `Status` uses the task-lifecycle vocabulary below. The [workflow policy](../policies/workflow-policy.md) also describes broader project phases: record those separately as `Workflow phase`. When correlating execution, ticket `ACTIVE` corresponds to workflow `IN_PROGRESS`, and ticket `REVIEW` to workflow `CODE_REVIEW`. PRODUCT/ARCHITECTURE and APPROVED/RELEASE are workflow phases, not extra ticket statuses; their approvals and release gates still apply. Record cancellation as the workflow policy's CANCELLED with its CEO/PM authorization and a ticket disposition, never as DONE; cease execution and have EM reconcile the ticket status without inventing a lifecycle transition. Status does not replace phase ownership.

Persist an authorization receipt: who requested the work, the request text or faithful scope excerpt, date/reference, permitted actions and retained restrictions. Copy enough substance to remain usable without the conversation. A newer explicit instruction supersedes only the restrictions it changes. Documentation persistence permission does not authorize product implementation. `READY` means prepared, not permitted; apply the receipt and current instructions before starting. Preserve dry-run/read-only restrictions until explicitly superseded for the relevant action.

| Transition | Authority and required evidence |
| --- | --- |
| Create BACKLOG | EM records owner, objective and known dependencies. |
| BACKLOG -> READY | EM verifies lifecycle readiness and required product/architecture decisions from their owners. |
| READY -> ACTIVE | Assigned owner starts authorized work after EM assignment and rechecks dependencies. |
| ACTIVE -> REVIEW | Assigned owner records completed work and applicable local verification. |
| REVIEW -> QA | Assigned reviewer records review approval. |
| QA -> SECURITY | QA records acceptance evidence; Security review remains required when applicable. |
| SECURITY -> DONE, or last applicable stage -> DONE | CEO verifies all applicable gates and Definition of Done, including DevOps release evidence when deployment occurs. EM records the authorized transition. |
| Any unfinished status -> BLOCKED | Assigned owner or EM records reason, impact, blocking decision/dependency IDs, prior status and escalation owner. |
| BLOCKED -> READY | EM verifies resolution evidence from every decision/dependency owner and rechecks readiness; execution still requires authorization. |
| READY -> BACKLOG | EM records missing preparation or changed scope. |
| REVIEW / QA / SECURITY -> READY | The corresponding reviewer, QA or Security records failed criteria; EM assigns corrective work and invalidates affected downstream approvals. Use BLOCKED instead if a decision/dependency is unresolved. |
| DONE -> BACKLOG or BLOCKED | CEO authorizes reopening with reason and affected evidence; EM records the transition. |

PM owns product approvals, CTO architecture approvals, the assigned engineer implementation evidence, the reviewer review approval, QA functional approval, Security security approval, DevOps release approval and CEO final approval. A skipped gate requires its owner to record `NOT_APPLICABLE` with rationale; existing policies still determine applicability. There is no direct BACKLOG -> DONE transition. EM records status changes but cannot substitute for another role's approval.

Track decision IDs and ticket dependencies explicitly. Unresolved blocking decisions propagate to all dependent tasks, including transitive dependencies. Resolving one blocker does not clear others or automatically advance a ticket. Independent preparatory work can proceed only within its own ready, authorized scope.

Retain a transition log in each ticket: previous status, new status, actor/role, UTC timestamp, reason and evidence/approval links. Append entries rather than replacing history; revision metadata alone is insufficient transition provenance.

## Recipient acknowledgement

Delivery starts with receipt status `PENDING`. The named recipient reviews source integrity, scope, blockers and next action, then records `ACCEPTED` or `CHANGES_REQUESTED` with actor/role, UTC timestamp, delivery path/hash and rationale. Acceptance confirms receipt of usable context only; task closure, gate approval and execution permission remain separate.

Keep the published delivery immutable. Append acknowledgements as new immutable sibling files `<id>-receipt-<sequence>.md` under the same handoff directory, using the receipt section of the template. Link each receipt to its delivery and previous receipt (or NONE); a derived index may point to the latest receipt. An absent receipt means PENDING. Changes to delivery content require a successor handoff with a fresh PENDING receipt, not editing an accepted delivery. A CHANGES_REQUESTED receipt leaves affected next work awaiting reconciliation; it does not silently change ticket status.

## Publish a checkpoint

1. Update authoritative documents and tickets within assigned ownership. Retain unresolved decisions and distinguish planning from implementation and executed verification.
2. Validate links, IDs, dependencies, transition authority and evidence. Record revisions and hashes of the finalized sources; exclude self-hashes and subsequently updated derived indexes from this source manifest.
3. Publish a new handoff ID with its predecessor, authorization receipt, source manifest, completed work, blockers, next owner and next permitted action. Use explicit `NOT_RUN` for unexecuted checks. Preserve previous handoffs.
4. Refresh derived state indexes and publish the current-handoff pointer in `company-state.md` last. If publication is interrupted, retain the previous pointer and reconcile partial writes before a later publication. Version the artifacts through the authorized repository workflow; this protocol does not grant commit or push permission.

## Resume and reconcile

1. Read `AGENTS.md`, applicable role instructions, `company-state.md`, the current handoff and its linked canonical documents/tickets. If the pointer is missing, inspect candidate handoffs and validate their sources before selecting one; a filename alone is not proof of completion.
2. Check the authorization receipt against current instructions. Inspect current Git/local changes and compare source revisions and hashes. Missing sources, contradictory approvals, or changed dependencies require reconciliation by their owners before affected execution. Preserve unrelated local work.
3. Treat stale indexes as rebuildable. Treat a handoff with changed source content as historical: revalidate affected decisions, tasks and evidence, then publish a successor. Never choose between conflicting product/technical claims merely by newest timestamp; obtain the appropriate owner's resolution.
4. An interrupted `ACTIVE` ticket is not evidence of a live agent or completed work. EM checks artifacts and the former owner's evidence, records recovery, then returns it to READY for authorized reassignment or BLOCKED for unresolved conditions. Repeat only verification invalidated by changes or missing evidence.
5. Resume when scope, source consistency, dependencies, ownership and permitted next action are established. Otherwise record the affected blocker; independent work remains eligible. A receipt or source with unverifiable provenance cannot support a new approval.
