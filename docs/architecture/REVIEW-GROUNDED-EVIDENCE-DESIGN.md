# Review grounded evidence design

Status: PROPOSED; implementation NOT AUTHORIZED. Revision: 1. Updated: 2026-10-06 (America/Buenos_Aires).
Base: `6ba0fd52728cdeb08313e51ad5244b70d5dab72f`; branch: `design/review-grounded-evidence`.
Author: external Runtime Reliability / Review Systems Architecture. Receipt: PENDING external design audit.
Authorization: external design request, attachment `a8aab21c-135d-42e9-a919-99e9c9f5151f/Texto pegado.txt`.
Scope: this document and regression specification only. No production, schema, test, policy or lifecycle edits; no providers, QA, E2E, merges or implementation PR.

Principles: **CORRECT FAILURE > FALSE SUCCESS**, **EVIDENCE BEFORE CLAIMS**, **CONFIGURED ≠ AVAILABLE ≠ CAPABLE**.

## 1. Incident

Classification: **REVIEW false approval / provider semantic failure**.

Clean Headless Run A recovery AICO-002 was owned by CTO. Its corrective completion was valid JSON, but report_markdown contained approximately 1293 characters ending at `## 3. Data Contract` and an unfinished fenced JSON object. Architecture/component outlines existed; substantive implementation plan, completed contracts, risks, migration strategy, ADR and explicit questions/blockers did not follow. ADR is conditional in the role contract; this incident does not make it universally mandatory.

Task result self-attested all outputs. Review returned APPROVE with empty missing/defect arrays. Captured response recognized missing plan content but inferred context truncation and trusted result claims. The inference was false. Runtime advanced REVIEW→QA. QA was not subsequently executed; recovery remains frozen.

Retained evidence root, outside this source worktree: `Z:/repos/ai-company-os/temp-tests/headless-runtime-e2e-2026-10-04/`. Paths below are audit locations, not portable future test dependencies:

| Evidence | Location beneath retained root |
|---|---|
| Owner raw completion | `run-a-recovery/03-cto-corrective/transport/45dd0cdf481442048bf9ec0c2330e756-response.json` |
| Primary report | `run-a-recovery/fixture/docs/engineering/agent-reports/AICO-002.md` |
| False result claim | `run-a-recovery/fixture/docs/engineering/results/AICO-002-result-002.md` |
| Review transport | `run-a-recovery/03-cto-corrected-review/transport/a7845488f12a479580ec8e25931fa3a8-{request,response}.json` |
| False approval | `run-a-recovery/fixture/docs/engineering/reviews/AICO-002-review-002.md` |
| Independent correlation | `cto-recovery-false-approval-forensic.md` |
| Frozen identity | `frozen-run-a-recovery.json` |

Historical originals remain immutable. Hidden reasoning is not an input to the proposed contract; the forensic observation explains the incident only.

## 2. Proven facts and hypotheses

Facts: actual Review message content totaled about 80,738 characters. Full persisted report and full CTO contract were present verbatim after CRLF normalization. Owner raw structured report was already incomplete. Result Changed Artifacts named only that report; no alternative architecture deliverable supplied the missing outputs. Review output was formally consistent. Retained requests, responses and artifact snapshots correlate these facts.

Hypothesis: explicit per-output primary citations and authority separation reduce this failure class. This requires evaluation. Neither better prompting nor valid citations prove semantic quality; no claim of eliminating all false approvals is justified.

## 3. Non-causes

There is no demonstrated deterministic Review context truncation, persisted-report loss or missing role contract in this incident. The short report is the actual owner output. This design addresses authority and grounding; existing protected evidence budgeting remains applicable, not redesigned.

## 4. Current trust boundary

Current integrated source matches the expected contract:

- `scripts/run-gate-agent.ps1:420–425` requires owner-contract comparison, substantive outputs and CHANGES_REQUIRED for material omissions; `:430–435` prohibits invented evidence and correlates explicit artifact paths.
- `schemas/review-result.schema.json` requires decision/findings/verification/missing/defect arrays, rejects extra fields, and contains no per-output grounding records.
- `scripts/validate-gate-result-semantics.ps1:1–4` accepts only JsonPath; `:46–65` checks empty/nonempty decision arrays without a trusted artifact manifest.
- `scripts/provider-router.ps1:680–732` validates and permits one same-provider semantic repair, then existing fallback. Validator calls carry JsonPath, not evidence identity.
- `scripts/run-gate-agent.ps1:454–465` invokes routing and revalidates before lifecycle intake. This second boundary also needs the same future trusted snapshot.

Formal consistency does not prove factual completeness. No contrary current-main behavior was found.

Existing tests include `test-gate-semantic-validator.ps1`, `test-role-deliverable-gate-validation.ps1`, `test-review-gate-provider-reliability.ps1`, `test-gate-artifact-identity.ps1`, `test-gate-authoritative-context.ps1`, `test-gate-evidence-preservation.ps1`, `test-implementation-gate-candidate-context.ps1`. They verify formal semantics/context preservation, not the truth of model completeness assertions. Retain them in future implementation.

## 5. Authority hierarchy

**Primary:** actual owner report for planning; explicitly declared actual implementation candidate for implementation. Additional owner artifacts are eligible only when canonical task/dispatch and engine safe inventory identify delivered outputs. Changed Artifacts can locate candidates but cannot grant primary status to arbitrary prose, unrelated tasks or unverified paths.

**Secondary:** result summary, verification prose, decisions, self-attestation and artifact names. Retain separately labeled context; exclude their text from positive evidence citations.

**Requirements:** canonical task/criteria and owner role establish obligations, not delivered proof. Citing a requirement cannot satisfy it.

`SELF-ATTESTATION ≠ DELIVERABLE` and `RESULT CLAIM ≠ PROOF OF OWNER OUTPUT`.

No second gate, lifecycle or scoring service. Review judges semantics; engine checks provenance of explicit assertions.

## 6. Alternatives

| Strategy | Deterministic benefit | Failure modes / semantic limits | Portability / complexity |
|---|---|---|---|
| Exact excerpt + artifact identity without location | Proves text occurs in supplied primary artifact | Duplicate occurrences ambiguous; fuzzy matching admits altered text; existence does not prove relevance | Simple JSON, low overhead |
| **Normalized line range + exact excerpt + engine snapshot identity** | Unique location, duplicate-text disambiguation, excerpt validated at that location | Long physical lines need full quotes or a future locator extension; newline rules mandatory; true irrelevant quote remains possible | Windows/Linux, basic JSON types; modest labels/quote overhead |
| Raw byte offsets + raw SHA256 + excerpt | Unambiguous byte identity and substitution protection | Providers count UTF-8 bytes poorly; CRLF shifts offsets; Unicode and encoding cause unnecessary repair | Portable code, poor model usability |
| Section identity + digest | Compact citations | Markdown heading/fence/nesting ambiguity, duplicate sections and truncated sections; structural bias; digest still not semantic proof | More parser complexity; provider should not compute hashes |
| Engine numbered fixed text chunks + excerpt | Bounded locators for very long lines | Boundaries split context; snapshot binding still needed; more labels | Portable future extension, unnecessary for captured 1293-character report |

Choose normalized lines with exact excerpt, bound to an immutable engine manifest. No provider-computed hash/byte arithmetic. Headings or keywords never establish completion. Parsing trusted requirement declarations only identifies obligations, not evidence that they were delivered.

## 7. Recommended minimal architecture

### Immutable invocation snapshot

Capture every eligible primary artifact once through existing safe path/candidate guards. Retain raw bytes/SHA256, strict UTF-8 normalized text/SHA256, namespace, task ID, candidate registration/branch identity, relative path, opaque artifact ID, line count and authority class. Raw and normalized views are distinct; never normalize originals in place.

Bind an invocation-local snapshot ID to a retained canonical manifest digest. Provider cannot create authority by echoing IDs. Supply exactly the captured normalized primary text with engine line labels outside the artifact content. Label result metadata SECONDARY SELF-ATTESTATION — NOT ELIGIBLE POSITIVE EVIDENCE.

Repair, fallback and final intake use the same manifest; validation must not reconstruct evidence from mutable live files. Before intake, safely compare current raw source digests and task/role/dispatch/candidate identity. Drift invalidates invocation, even if normalized text is unchanged. A fresh invocation is required; no automatic task mutation.

### Engine-owned obligation coverage

A provider-generated checklist can omit the missing plan. Engine must issue the full obligation list from owner Output declarations and canonical task acceptance items, retaining source path/digest/locator. Require exactly one assessment per engine ID: duplicates, omissions, invented or renamed IDs fail.

Enumerate existing declared bullets/checkboxes without semantic rewriting; preserve compound clauses. Conditionality needs an explicit reviewed mapping keyed to role-contract version, not guesses from arbitrary natural language. Unsupported/ambiguous shapes fail preparation rather than silently shrinking coverage. Future implementation must document every shipped role's extraction coverage and map relevant Responsibilities to Output/task criteria or explicitly account for them. This is a small declaration adapter, not a generic semantic synthesizer/scoring framework.

CTO coverage includes all seven Output items and task requirements for explicit questions/blockers. ADR remains conditional. Conditional NOT_APPLICABLE needs reason, primary fact citations and cited source condition; reviewer judges necessity. It cannot waive unconditional plan/risks/migration. Engine checks conditional permission and provenance, not correctness of necessity. Unresolved applicability should yield CHANGES_REQUIRED rather than a completeness claim.

### Normalized line/excerpt primitive

Normalization `utf8-lf-v1`: strict UTF-8; initial BOM removed only in textual view; CRLF and lone CR converted to LF. Preserve all other whitespace, Unicode code points and trailing LF. No NFC/NFKC, trim, case fold, tab expansion or Markdown rendering. Text digest hashes UTF-8 without BOM. Lines are one-based; trailing LF produces a deterministic final empty line. Excerpt equals inclusive selected normalized lines joined with LF, without adding a final join newline. Tests define this convention explicitly.

Reference fields: engine artifact ID, start/end line, exact excerpt. Manifest supplies path/digest for audit; provider echoes snapshot/artifact IDs, not computed SHA256. Line range disambiguates duplicate text. Compare ordinally, not by locale. Small quote differences fail and may be repaired. Oversized unbroken lines produce explicit unsupported-evidence/budget failure; no clipped quote acceptance. A versioned chunk locator can later extend coverage if real evidence requires it.

Proposed ceilings for audit: 64 obligations, 3 references per assessment, 16 lines and 2048 UTF-8 bytes per excerpt, total excerpt bytes32KiB, 20 eligible primary artifacts. These permit the captured report's single physical line. Check aggregate limits before expansion. Existing file/candidate/budget caps still apply. Calibrate ceilings across roles/models before rollout; exceeding them fails visibly, never omits requirements. Limits do not assert that an available local provider is capable.

## 8. Illustrative structured contract

Not an implemented schema. Retain current fields; add version, snapshot ID and assessments. Basic JSON objects/arrays/strings/integers/enums, explicit required fields and no dynamic property names/schema conditionals. Cross-field rules stay local; existing transport adaptation cannot weaken canonical validation.

```json
{
  "contract_version": "review-grounding-v1",
  "snapshot_id": "review-0042",
  "recommendation": "APPROVE",
  "findings": "Applicable outputs have cited primary content.",
  "verification": "Reviewed snapshot review-0042.",
  "missing_required_outputs": [],
  "deliverable_defects": [],
  "assessments": [
    {
      "required_output_id": "owner-output-02",
      "status": "SATISFIED",
      "rationale": "These steps define implementation order and checks.",
      "evidence": [{
        "artifact_id": "primary-01",
        "start_line": 31,
        "end_line": 33,
        "excerpt": "1. Add storage operations.\n2. Wire CLI commands.\n3. Verify persistence across processes."
      }]
    }
  ]
}
```

Only one illustrative row; real APPROVE requires the entire engine obligation set. Statuses: SATISFIED, UNSATISFIED, NOT_APPLICABLE. Rationale always required. Missing-output negatives can have empty evidence; SATISFIED requires primary citations; conditional N/A requires primary facts and conditional authority. Assessments are the authoritative positive judgment contract. Engine cannot prove free-prose assertions merely by parsing them.

## 9. Deterministic validation algorithm

1. Build trusted declaration coverage/eligible manifest. Reject unsupported shapes, empty/oversized obligations and missing source identity before generation.
2. Capture immutable raw/normalized views and manifest digest; annotate primary evidence and separate secondary context. Full protected snapshot must fit effective candidate budget; otherwise existing precall reject/fallback uses unchanged snapshot.
3. Validate canonical JSON schema/version/exact snapshot ID/types/aggregate limits. Transport adaptations never remove local checks.
4. Require assessment ID exact-set equality with obligations; reject duplicates, missing/unknown IDs, blank rationale/invalid status.
5. Resolve citations exclusively through trusted manifest IDs; reject secondary, requirement-only, unrelated namespace/task, deleted/absent or unsupplied artifacts. Never read provider paths/URLs.
6. Verify normalized digest against captured text, inclusive bounds and exact ordinal excerpt. No fuzzy matching, relocation, trimming or rendered-Markdown comparison. Verify raw captured identity separately.
7. APPROVE requires all mandatory rows SATISFIED, only authorized conditional N/A, valid citations and existing empty defect arrays. CHANGES_REQUIRED requires concrete missing output/defect and corresponding UNSATISFIED assessment or concrete deliverable defect. Missing-output negatives need no invented quote; any supplied citation must still be valid.
8. Return usable judgment or typed unusable-output reason. Grounding valid does not mean semantic quality PASS.
9. Revalidate after router success against same manifest; compare current raw/source authorization identities immediately before intake. Serial operation/lock must prevent writes racing check and transition. If current coordination cannot guarantee that window, implementation must fail closed or bind intake to immutable candidate revision, not read a different live artifact.
10. Only usable/current decisions enter existing gate recording/lifecycle. Persist snapshot identity and validated references for audit.

## 10. Failure semantics

Invalid APPROVE is **unusable provider output**, neither accepted approval nor auto-generated CHANGES_REQUIRED. No valid Review artifact/downstream approval/state mutation. Task stays REVIEW. Valid CHANGES_REQUIRED retains REVIEW→READY. All providers exhausted: fatal operation with task, gate, provider, typed grounding reason, affected obligation/artifact and next action; task REVIEW. Retain rejected attempts separately from valid gate records.

Missing coverage, secondary citation, locator mismatch and stale snapshot are distinct errors. Do not infer owner semantic defects from a provider's citation failure. Preparation/staleness errors are invocation errors, not repairable model judgments.

## 11. Repair and fallback

Reuse existing single same-provider semantic repair for schema/coverage/citation response errors against unchanged snapshot. Feedback identifies rejected fields and trusted IDs; no secrets/hidden reasoning/artifact instructions become policy. Regenerate entire structured judgment, potentially truthful CHANGES_REQUIRED. Validate from scratch without relaxing limits or dropping obligations.

Failed repair uses existing Auto fallback and unchanged free/paid order. Explicit provider has no hidden fallback. Every attempt uses same manifest. Drift/missing source/ambiguous declarations stop invocation, without generating against stale evidence. Future plumbing must pass trusted manifest context through BOTH router validator calls and final pre-intake guard; JsonPath-only is insufficient.

## 12. Real regression fixture plan

Future implementation creates a sanitized immutable fixture, not this task. Copy actual incomplete report, false result prose, relevant task criteria, CTO contract and explicit structured APPROVE fields. Preserve unfinished ending and task/report relationships. Remove credentials, account/endpoint metadata, absolute host paths, unrelated telemetry and all hidden reasoning. Record original raw SHA256/extraction locator, sanitation policy and sanitized SHA256. Sanitation cannot remove the contradiction or repair the report. Tests use fixture-relative paths, no Z:, keyring or network; originals untouched.

Three deterministic tests:

1. Replay captured ungrounded APPROVE: reject missing v1 records before intake. Fake repeating it through bounded repair/fallback leaves REVIEW, no approval/QA transition.
2. V1 adaptation citing genuine false-summary text only: reject secondary authority despite exact quote/hash; cannot manufacture primary outputs.
3. Fake repair returns truthful CHANGES_REQUIRED with concrete missing outputs: accept negative and canonical READY transition; preserve rejected attempt separately.

Separate semantic evaluation uses this sanitized contradiction and expects CHANGES_REQUIRED. Optional real-provider eval requires separate authorization and reports variability. A SATISFIED assertion using unrelated genuine architecture quotes can pass provenance checks; semantics must reject it. Do not claim synthetic grounding tests prove all models now detect omissions.

## 13. Adversarial regression matrix

20 cases specified; tests NOT_RUN.

| ID | Case | Expected |
|---|---|---|
| A | Complete deliverable, full coverage/exact primary citations | Usable APPROVE, normal QA transition after identity check |
| B | Missing primary plan; false result assertion cited | Reject secondary authority, no mutation |
| C | Fabricated/out-of-bounds/reversed/noninteger range | Reject locator |
| D | Material or tiny quote difference | Exact mismatch; bounded repair possible |
| E | Another task/arbitrary path/unsupplied artifact | Reject manifest lookup/authority |
| F | Raw hash drift, even normalized-identical rewrite | Invalidate before intake; fresh invocation |
| G | Separate CRLF/LF/BOM captures | Equivalent normalized citations, each bound to own raw identity; no cross-snapshot substitution |
| H | Duplicate text at different locations | Explicit range resolves location; no relocation |
| I | Primary/result contradiction | Primary wins; result cannot substitute |
| J | Correct missing-output CHANGES_REQUIRED | Accept concrete negative without forced positive citations |
| K | Real captured legacy APPROVE unchanged | Reject missing v1 coverage |
| L | Missing/duplicate/unknown criterion IDs | Reject checklist shrinkage |
| M | Repair/fallback across providers | Same snapshot/obligations/bounds, unchanged policy |
| N | All attempts repeat invalid approval | Task REVIEW, no valid record, fatal reason/next action |
| O | Long line/report, quote aggregate or protected context over budget | Visible precall/intake failure, no clipping |
| P | Astral/combining Unicode, tabs, spaces, trailing LF/lone CR | Specified normalization and ordinal exact matching |
| Q | Traversal/UNC/drive, symlink/reparse swap, secret path | Reject before source access; no secret exposure |
| R | Conditional ADR N/A versus unconditional plan N/A | Conditional fact-grounded semantic exemption allowed; unconditional rejected |
| S | Genuine primary quote irrelevant to asserted output | Provenance may pass; semantic eval exposes limitation, never deterministic quality PASS |
| T | Deleted source/drift during repair/intake or declaration ambiguity | Stop invocation, no mutation |

M includes schema-adapter/custom-router compatibility subcases. Preserve existing negative decision/role/context tests. Case S intentionally exercises the semantic boundary; keywords cannot replace judgment.

## 14. Security

Manifest limits source reads to canonical task-bound roots and explicit candidate namespace with existing safe-path/secret/reparse/common-Git-dir guards. Resolve filesystem case correctly but compare IDs ordinally; reject alias collisions. No provider-controlled traversal, drives, UNC, URLs, symlink reads or arbitrary artifact selection. Capture hash/text from the same safely opened byte stream, avoiding independent-read races.

Artifacts are untrusted data, including prompt-like strings or forged line labels. Authority/IDs come from engine framing, not content. Never interpolate excerpts into shells or paths. Secret-bearing primary sources cannot silently be redacted then treated as full eligible evidence; exclude/fail preparation visibly. Redact diagnostic errors and sanitize regression transport carefully.

Digest proves identity, not safety/truth/ownership. Snapshot ID is trusted only through retained engine binding, not echo. Lock coordination and raw identity prevent stale intake. Historical approvals keep provenance; no retroactive rewrite/status changes.

## 15. Compatibility

Basic provider-portable JSON types; existing adapter transformations may preserve compatibility but cannot bypass canonical checks. No model reasoning format, citation API, embeddings or new provider abstraction. Hashes engine-side reduce small-model arithmetic burden. Availability is not capability.

Labels/manifests/excerpts increase prompt/output size; count actual characters/bytes in existing effective budgets. Explicit limits bound growth, while unfit evidence fails closed. QA/Security schemas/policies unchanged in initial scope. Binary/unsupported primary text formats fail visibly pending a reviewed locator extension.

## 16. Migration

New Review invocations require explicit v1. Legacy ungrounded APPROVE is unusable; may take single repair/fallback, never accepted through an optional mode. Ship schema, manifest plumbing, validator, intake guard and packaging/install/update together after authorization. Old gate artifacts stay immutable and auditable; absence of v1 identifies legacy provenance, without automatic reopening or continuation.

Rollout: sanitized fixture, compatibility regressions, existing full suites, then separately authorized provider eval. Rollback may visibly disable v1 Review execution; never silently allow ungrounded approval for invocations claiming v1. No provider order/free policy/TUI/task-state changes in this design.

## 17. Non-goals and decision test

No deterministic proof of architecture quality, sufficiency, relevance or model honesty. No keyword/heading completion, semantic-scoring framework, vectors, self-learning, hidden reasoning, second lifecycle or unrelated fixes.

| Question | Answer / boundary |
|---|---|
| 1 Captured approval prevented? | Yes: missing grounding and secondary-only adaptation rejected; not all future dishonest valid quotes. |
| 2 Correct APPROVE allowed? | Yes with complete coverage/exact primary citations and reviewer semantic judgment. |
| 3 Fabricated evidence passes? | Nonexistent/altered references no; genuine but irrelevant quotes can pass provenance. Case S retains that limit. |
| 4 Self-attestation substitutes? | No, secondary IDs ineligible. |
| 5 Headings/keywords proof? | No; trusted declaration parsing only identifies requirements. |
| 6 Hidden reasoning? | Not required or consumed. |
| 7 Provider-specific? | No. |
| 8 Second lifecycle? | No. |
| 9 Invalid APPROVE silently success? | No coercion or legacy acceptance. |
| 10 Fail closed? | Yes at preparation, response and intake. |
| 11 Immutable history? | Yes, new snapshot/sanitized copy only. |
| 12 Real regression? | Yes, section12, no reasoning/network dependency. |
| 13 Material token increase? | Yes at configured maxima; actual overhead measured per candidate. |
| 14 Bounded? | Yes counts/aggregate/effective budget; no evidence trimming. |
| 15 Free-first/agnostic? | Yes, unchanged order/cost policy. |

## 18. Future implementation plan and checkpoint

Proposed steps, NOT EXECUTED:

1. Approve authority/locator/failure design, obligation declaration mappings and limits/conditional policy.
2. Implement small immutable snapshot/manifest helper with existing guards; establish raw/normalized conventions and mutation-lock boundary.
3. Add coverage mappings for shipped role/task contracts, Review v1 schema and manifest-aware validation; no semantic keyword heuristics.
4. Pass same manifest through initial/repair/fallback and pre-intake checks; retain rejected attempts securely.
5. Create sanitized real fixture/provenance, implement20-case matrix and existing schema/context/packaging regressions.
6. Run focused/full suites; separately authorize real-provider semantic eval. Deterministic PASS does not certify E2E/TUI.

Open implementation audit decisions: exact role mappings/responsibility coverage, mutation-lock ownership, calibrated limits and retention/redaction policy. Resolve before rollout. None requires implementing code in this task.

Task validation: git diff --check and authorized-file/status verification only. Runtime tests NOT_RUN (design only). Runtime behavior UNCHANGED. Historical evidence read-only. Both diagnostic A fixtures stay frozen, B NOT_STARTED. PR NONE. Next exact action: External Orchestrator audits this document and authorizes a separate implementation task if accepted.
