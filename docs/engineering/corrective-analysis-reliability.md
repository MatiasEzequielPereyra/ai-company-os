# Corrective Analysis Reliability

Project: AI Company OS
Revision: 2
Updated: 2026-10-03 (UTC)
Updated by: CODEX-ORCHESTRATOR
Base: fd6c187f8c34d72a3da8b63d139b16bb3e6afa40
Status: READY_FOR_EXTERNAL_ORCHESTRATOR_RE_REVIEW

## Authorization and scope

The user's 2026-10-03 Corrective Analysis Reliability request authorizes an isolated worktree from fetched origin/main, implementation of analysis BLOCKED semantics and corrective evidence preservation, focused/full validation, commit, branch push and a PR against main. No merge, subsequent ticket or Run #5 is authorized. Acceptance Run #4 fixture, engine, harness and evidence remain frozen; no provider invocation or artifact/state modification there is allowed. Historical dirty checkout changes remain protected.

## Confirmed defects addressed

Run #4 AICO-002 knew that its CTO-owned ADR output was absent but returned BLOCKED without identifying an external impediment. Analysis intake previously accepted that outcome and changed ACTIVE to BLOCKED. Its repeated analysis context was also truncated as a generic prefix, without protecting the corrective delivery and findings. This patch does not reinterpret or change any acceptance artifact.

## Structured analysis outcome contract

`schemas/agent-result.schema.json` and `schemas/engineering-plan-result.schema.json` add an optional `execution_blocker` object. Existing valid COMPLETED payloads continue to omit it. For BLOCKED, `scripts/validate-analysis-result-semantics.ps1` requires it, with:

- `kind`: missing_evidence, access_denied, authorization_required, external_decision or unsatisfied_dependency;
- `prerequisite`: the unavailable external requirement;
- `evidence`: concrete evidence of that requirement being unavailable;
- `resolution_owner`: the person/role that can resolve it;
- `why_role_cannot_resolve`: the authority/access/evidence boundary preventing delivery;
- `role_can_resolve`: false.

`owned_output_pending` is representable for diagnosis but is explicitly rejected semantically, as is `role_can_resolve=true`, missing fields, placeholder evidence or an empty/NONE blocker summary. Missing role-owned outputs, defects and product readiness findings do not supply an execution impediment. COMPLETED still requires a substantive deliverable and no missing outputs; a declared execution blocker contradicts COMPLETED.

The analysis runner passes this validator to the existing router semantic repair mechanism for every analysis role. An invalid structured outcome is repaired once by the same provider; existing permitted fallback behavior remains in effect after failure. No automatic BLOCKED-to-COMPLETED conversion occurs. The runner validates again before publishing the primary report, numbered result or lifecycle transition, protecting callers with alternate routers. Engineering Manager executable-plan semantics are composed through the existing validator unchanged.

Validated structured blockers are also recorded in the numbered task result, so their evidence survives the fixed runtime JSON being overwritten. The optional intake parameter preserves existing manual and writable callers; this new contract applies at the analysis runner boundary.

This contract checks structured coherence and required evidence declarations; it does not independently verify every natural-language assertion made by a provider. Independent review and escalation remain necessary.

## Corrective evidence and budgets

Before invoking a provider or overwriting its runtime JSON/report, `build-corrective-analysis-context.ps1` selects the currently pending corrective source: latest numbered Review CHANGES_REQUIRED, QA FAIL or Security FAIL. Append order in the canonical task Transition Log distinguishes gate cycles, including transitions recorded in the same second. The current artifact outcome clears a superseded failure; Review APPROVE and QA PASS transitions supersede earlier gate failures. When legacy records have no canonical transition provenance, unambiguous Recorded timestamps identify the latest source; tied or absent timestamps across competing gates fail closed. Only the selected failing artifact supplies protected corrective findings. Task/owner identities and gate heading identities must agree across canonical sources.

The protected envelope contains canonical task, original role contract, original dispatch, previous owner report, latest numbered result, authoritative failing review or gate and explicit corrective findings. Concrete Changed Artifacts references are resolved within the project, including semicolon-separated references. Sensitive paths, traversal and reparse-point ancestors are rejected. The builder is read-only.

Only append-only task Evidence, Transition Log and Notes are compacted to their last three nonempty lines, with an explicit omission marker and full source SHA256. Objective, requirements, acceptance criteria, dependencies and other task sections remain verbatim. Reports, results, review findings and role/dispatch contracts remain complete.

The router reserves the effective provider/hardware budget for the protected envelope, then uses remaining space for general repository context. `context_input_chars` includes the assembled envelope, separator and general context; `context_chars` records what is sent. If essential evidence cannot fit, it is never silently truncated: an explicit provider fails before invocation; Auto skips that candidate and continues only through its existing permitted order/policy. Codex receives the same corrective envelope in its prompt, while retaining read-only repository inspection. Gate compaction and writable routing are unchanged.

No general historical subsystem was introduced. Existing numbered results and latest review plus the still-current primary report reconstruct the retry before overwrite. A failed semantic repair leaves prior primary report/results and task state intact; raw provider runtime output remains diagnostic data, not lifecycle approval.

## Regression and verification

- `test-analysis-result-semantics.ps1`: 12 structured contract cases, including legacy COMPLETED, own-output BLOCKED rejection, legitimate external BLOCKED and unchanged Engineering Manager semantics.
- `test-corrective-analysis-context.ps1`: all seven sections, large operational history, effective-budget preservation, identity/secret/traversal/link checks, first-attempt custom IDs, latest APPROVE, insufficient-budget rejection and permitted Auto fallback without paid-policy bypass.
- `test-corrective-analysis-reliability.ps1`: actual runner/router/lifecycle with deterministic adapters: first COMPLETED -> independent CHANGES_REQUIRED -> corrective activation -> owned-output BLOCKED rejection -> same-provider semantic repair -> valid COMPLETED/REVIEW. Also legitimate external BLOCKED, invalid repair exhaustion and preservation of prior report/results.
- Existing completion, Engineering Manager focused E2E, installer/update and package contracts were retained and extended for the new helpers.

Final results: Python **185 PASS**; Windows PowerShell 5.1 smoke/contracts **52/52 PASS**; npm **2 PASS**; exact installed tarball release E2E **PASS** (aico new/install/update, Python/TUI bootstrap/import, managed helpers and preserved user files). No live provider calls were used; provider regressions use fake adapters/resolvers.

Initial failures were retained in external logs rather than hidden: pytest default temporary directory permission errors (87 pass / 98 setup errors); PowerShell child-process temporary-directory access/8.3-alias failures; release E2E Push-Location with LANAVE~1 alias. Final runs used a fresh pytest --basetemp, isolated TEMP/TMP for full smoke and RUNNER_TEMP for release E2E. Focused integration also caught missing installer helper registration, an over-restrictive task ID grammar and a completion diagnostic compatibility mismatch; these were fixed and the corresponding tests rerun before the full green suite.

External evidence: Z:/repos/ai-company-os/temp-tests/corrective-analysis-reliability-evidence (authorization, initial/final logs and packed tarball). No release/publish or merge performed. Next action: External Orchestrator reviews the PR; acceptance continuation requires separate authorization.

## PR #41 minor review revision

The external Orchestrator's REQUEST CHANGES — MINOR authorizes extension to QA FAIL and Security FAIL corrective analysis retries, updating this existing PR and all validation reruns. The previously approved structured BLOCKED contract and same-provider semantic repair remain unchanged.

Only the latest pending gate artifact is protected, followed by its explicit findings. Canonical Transition Log append order resolves same-second retry cycles. Successful subsequent Review/QA stages suppress historical failed sources. Fixed Security PASS/NOT_APPLICABLE replaces its FAIL outcome. Contradictory outcomes or competing equal timestamps without canonical provenance fail closed.

The existing integrated reliability regression now invokes actual canonical gate and activation scripts, then the actual analysis runner/router with a deterministic fake provider. QA FAIL follows Review APPROVE; Security FAIL follows Review APPROVE and QA PASS. Each case proves complete findings/evidence and the previous deliverable survive an oversized general context within 12,000 characters. Additional assertions reject ambiguous provenance and suppress stale Security failure immediately after subsequent Review APPROVE, before QA PASS. Existing Review CHANGES_REQUIRED and BLOCKED semantic repair cases stay green.

Revision validation: focused regressions PASS; Python 185 PASS; Windows PowerShell 5.1 full smoke/contracts 52/52 PASS; npm 2/2 PASS; installed packed release E2E PASS. Tarball SHA256: 0478AB0D0C9BB3472080B85A0175D7D9E4CE2C6E2D1061045EBED5DA5EE13685, 217 entries; six critical runtime/schema files byte-match source. Evidence: Z:/repos/ai-company-os/temp-tests/corrective-analysis-reliability-re-review-evidence. GitHub CI and final SHA are recorded in the external publication checkpoint after push.
