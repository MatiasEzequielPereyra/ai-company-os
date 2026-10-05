# Gemini engineering plan schema portability

Project: AI Company OS
Revision: 1
Updated: 2026-10-04
Updated by: Principal Runtime / E2E Engineer
Base: 35e8a0a581244d55344ddf96b0d71514ebc31157

## Authorization and preserved scope

The user authorized real headless E2E on fresh diagnostic copies, stopping on
defects and fixing deterministic engine failures in isolated worktrees with
regressions. No merge, Codex inference, paid route, historical Run 3/4/5/6 change
or canonical reference modification is authorized.

## Exact failure and controlled isolation

Run A completed PM and CTO through their real gates and finalization. EM's
OpenRouter result had valid executable work but an incomplete narrative report.
Independent Review returned CHANGES_REQUIRED. The canonical activation API
returned AICO-003 to ACTIVE. Its real corrective Gemini request failed HTTP 400
INVALID_ARGUMENT before producing a result; the task remained ACTIVE.

Original request/error evidence:
`temp-tests/headless-runtime-e2e-2026-10-04/run-a/04-em-corrective-01/transport`.
The model was the existing configured `gemini-3.5-flash-lite`.

Controlled real transport probes in `fix-03/schema-probes` used the same short
public prompt and a 256-token diagnostic output cap. The translated canonical
engineering plan schema returned HTTP 400. Removing all maxItems bounds returned
HTTP 200. A narrower probe removed only `executable_work.maxItems = 20` and also
returned HTTP 200, with remaining schema members and bounds unchanged. This
isolates the failing composite object-array bound from prompt length, sampling,
credential, model or task lifecycle. These probes do not count as E2E completion.

## Minimal correction and canonical safeguard

Gemini transport projection omits maxItems only for arrays of objects. All object
fields, required members, enum values, item schemas and minItems remain intact;
scalar-array maxItems remain intact. The canonical schemas are unchanged.

Gemini supports array bounds in general; this is a compatibility projection for
the demonstrated composite schema rejection, not a claim that all maxItems are
unsupported. Existing string-keyword normalization remains unchanged.

The local canonical JSON validator previously checked minItems but not maxItems.
It now checks maxItems, including zero, before item traversal. The router already
validates the original canonical schema before accepting the provider result and
mutating task/report lifecycle. Transport relaxation therefore does not authorize
more than 20 executable work items or otherwise relax canonical array limits.
No outcomes are coerced. Empty BLOCKED work and nonempty COMPLETED work remain
governed by the existing semantic contract.

## Verification and handoff

Focused regression uses the actual engineering plan schema and fake transport,
checks preserved required fields and enums, positive/negative canonical and
semantic cases, array upper boundaries and unchanged canonical schema bytes.
Full verification results and CI are recorded in external diagnostic evidence.

Local verification: focused regression PASS; Windows PowerShell 5.1 full smoke
56/56 PASS; Python 204 PASS; npm 2 PASS. Official runtime update preserved all
55 control-plane artifacts by exact hashes before resuming the pending task.

Recipient: CODEX-ORCHESTRATOR
Receipt: PENDING
Next permitted action: review the isolated correction; resume AICO-003 through
the real runner from its existing ACTIVE state after verified runtime update.
No lifecycle artifact is manually advanced or rewritten.
