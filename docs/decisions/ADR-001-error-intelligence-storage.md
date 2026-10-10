# ADR-001: Local storage and trust boundaries for Error Intelligence v1

- Status: Proposed for external review
- Date: 2026-10-10
- Base: `a5c030cfb83bc98bc7d3d009df616cc7e3590cf0` (`origin/main` as available locally)

## Context

AI Company OS has append-only operational telemetry at `.codex/runtime/metrics/events.jsonl`, but it is a derived project-local log with no incident model, history search, verification workflow, or installation scope. Existing provider redaction applies at a provider boundary; error history needs its own redaction because it can be called with arbitrary text. No cross-run incident knowledge store is present in this base. Existing debugging and citation worktrees are separate branches and are not capabilities in this base.

The MVP must persist across processes, be auditable, tolerate concurrent writers and corruption, and remain isolated from agents, task transitions, provider routing, gates, Skills, and evidence.

## Decision

Use Python's standard-library SQLite in a local per-user state directory. The default includes a short SHA-256-derived key of the installed package file path, so separate installation locations get separate databases; the source path itself is not persisted. Default Windows location is `%LOCALAPPDATA%\AICompanyOS\ErrorIntelligence\<installation-key>\incidents.sqlite3`; `AICO_ERROR_INTELLIGENCE_PATH` supplies an explicit absolute path. Other platforms use XDG state or `~/.local/state`. Project identifiers are mandatory on writes and reads; searches cannot cross projects.

Keep immutable occurrence and event rows. Exact duplicates share a stable incident family key and add a separately retained occurrence with its evidence. The initial incident summary is not replaced. SQLite transactions and a busy timeout serialize updates. Schema version is held in `PRAGMA user_version`; unknown versions, corruption, and unsafe paths fail closed. Corrupt files are preserved for manual recovery; no automatic reset or migration from JSONL is performed.

Redact common credential forms before persistence and bound every text field. Evidence is stored as caller-supplied text and is never opened as a path. A recorded diagnosis is unverified by default. Root-cause and correction verification require separate explicit calls with a verifier identity and non-empty evidence. Recommendations return deterministic match basis, confidence, and an equivalence flag; only verified fixes are returned as solutions, and a subsequently failed attempt suppresses that action.

## Trust limits

All stored summaries, evidence, fixes, and causes are untrusted data. They are not instructions, policy, authority, or evidence of equivalence. This package makes no model calls and is not imported by production runtime, task execution, Skills, provider routing, or gates. Verification metadata records what a caller asserted; the API cannot cryptographically establish that a human performed the review. Consumers must display stored content as quoted data and must not execute proposed actions automatically.

## Consequences

- No third-party dependency, network service, embedding, or model call is needed.
- SQLite provides atomic transactions and suitable local multi-process coordination with the standard library.
- Per-user state is outside a project's managed-file namespace and remains across repository changes.
- The installation may configure a distinct path where multiple installations share one OS account.
- SQLite is not a multi-host service; export/import, automatic collection, retention policy, encryption-at-rest, and runtime integration remain future decisions.
- Redaction is defense in depth, not a guarantee against every secret format. Callers should submit bounded, sanitized summaries and references instead of raw logs.

## Alternatives considered

- JSON/JSONL: already used for append-only telemetry, but lacks transactional updates, indexed matching, and safe concurrent read/modify/write for duplicate families.
- External database: adds deployment and operational dependencies without a v1 multi-host requirement.
- Conversation or repository state: conversation is not durable; project `.codex` data is in the wrong ownership/authority scope and may be copied or managed as project content.
