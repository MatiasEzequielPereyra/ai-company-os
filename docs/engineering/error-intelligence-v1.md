# Error Intelligence v1

## Repository audit and integration map

Audit base is local `origin/main` SHA `a5c030cfb83bc98bc7d3d009df616cc7e3590cf0`. A fetch was attempted on 2026-10-10 but DNS/network access to GitHub was unavailable, so this is the locally available remote-tracking ref, not a claim that GitHub was freshly checked. The requested app-managed worktree helper did not recognize this nested repository; an isolated Git worktree was created directly at `Z:\repos\ai-company-os\worktrees\error-intelligence-v1`.

The primary repository checkout already contained unrelated modifications and untracked evidence. They were left untouched. Existing Git worktrees include acceptance Run 01/02/04/05/06, Review Grounded Evidence, Grounded Citation Spans, debugging capability, corrective analysis, provider fallback, and other feature/review branches. These neighboring branches are not merged capabilities and were not changed. The current app task had no attached PR/worktree artifacts. GitHub active PR status could not be fetched without network access.

| Existing capability | Current responsibility | Error Intelligence boundary |
| --- | --- | --- |
| `.codex/runtime/metrics/events.jsonl` and `scripts/write-operational-event.ps1` | Local append-only lifecycle/provider telemetry; no raw provider content | Remains unchanged; incident store is separate and searchable |
| Router redaction in `scripts/provider-router.ps1` | Redacts configured provider secrets at provider error boundary | New API redacts common secret formats before persistence |
| Doctor/diagnostics in Python application and TUI | Current system/runtime diagnostics | No TUI or doctor integration in v1 |
| Review Grounded Evidence and citation spans | Gate evidence validation and citation grounding | Not modified and not used as memory authority |
| Skills under `.agents/skills/` | Feature, bug, architecture, code review, release, tests workflows | No Skills Orchestrator service or persistent error knowledge exists in this base; no Skills files are changed |
| Task lifecycle, provider router, writable runtime | Production task/provider behavior | No imports, hooks, prompt selection, automatic capture, or transitions are added |

## MVP API

`company_os.error_intelligence.ErrorIntelligenceStore` is explicit opt-in application code. It supports recording and reopening incidents, project-scoped deterministic search, duplicate family occurrence tracking, retrieval of every occurrence and append-only event, diagnosis, explicit root-cause verification, proposed corrections and contraindications, verification of a proposed correction, failed/inconclusive recovery records, regression markers, and verified solution lookup. It makes no provider or model calls.

Example:

```python
from company_os.error_intelligence import ErrorIntelligenceStore

store = ErrorIntelligenceStore()  # LOCALAPPDATA default or AICO_ERROR_INTELLIGENCE_PATH
incident = store.record_incident(
    project_id="my-service",
    component="provider-router",
    category="availability",
    error_type="TimeoutError",
    summary="Provider request exceeded configured timeout",
    evidence=["tests/test_router.py::test_timeout failed"],
)
matches = store.search(project_id="my-service", component="provider-router", error_type="TimeoutError")
```

Use absolute explicit database paths. Provide project IDs deliberately; the library does not scan the repository or collect task, run, system, or provider data. Avoid raw logs; redaction covers common bearer/API key/private-key patterns but is not exhaustive. Evidence strings are never opened, interpreted as paths, or executed. SQLite files should be included in the installation's normal local-data backup policy if retention matters.

Observed incidents and diagnoses are not verified causes. Verification requires an explicit verifier identity and evidence. These are auditable assertions, not cryptographic identity proofs. A verified correction is a recommendation only; this package never runs it. Search is deterministic: exact fingerprint gives confidence 1.0 and `equivalent=true`; component, class, and normalized text matches are lower-confidence similarities. Project IDs are required, so matches do not cross project boundaries.

## Persistence and recovery

- Windows default: `%LOCALAPPDATA%\AICompanyOS\ErrorIntelligence\<installation-key>\incidents.sqlite3`. The key is a short hash of the installed package module path; the path itself is not written to the store. Set the override per installation if application moves should retain the same store.
- Override: `AICO_ERROR_INTELLIGENCE_PATH` with an absolute path.
- Schema: SQLite `user_version=1`; standard library only.
- Duplicate records append an occurrence and event, preserving every evidence set, task/run reference, and the first summary.
- Corruption, unknown schema versions, relative paths, traversal components, symlinks, or non-file targets fail closed. A corrupt database is preserved; point the configuration at a new path only after retaining the old file for investigation.
- Local POSIX database mode is restricted to owner read/write; Windows relies on the user's Local AppData ACL.

## Verification plan

Deterministic tests cover restart persistence, schema/invalid fields, duplicate occurrences, concurrent threads using separate connections, corruption preservation, invalid/traversal paths, project isolation, credential redaction, unverified diagnosis, evidence-gated verification, failed-recovery suppression, similarity vs equivalence, and regression status. No test calls an external provider. Task/gate state, historical evidence, Review Grounding, citation spans, provider routing, retry policies, lifecycle, TUI, Skills, and provider models/configuration are outside the changed-file scope.

## Future plan (not implemented)

1. Consider operator-initiated capture during task execution with explicit scopes and redaction review.
2. Add an opt-in read-only pre-agent lookup after measured false-positive and contamination evaluation.
3. Define a Skills integration contract only if the Skills Orchestrator gains a suitable explicit consultation hook.
4. Evaluate deterministic ranking before local-model-assisted ranking; never make model conclusions authoritative.
5. Add provider failure aggregates, regression learning, a TUI review surface, and controlled export/import as separately reviewed features.

No automatic prompt injection, provider selection, workflow action, recovery execution, or security-rule learning is proposed for this release.
