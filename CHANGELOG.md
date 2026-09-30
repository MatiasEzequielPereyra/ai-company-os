# Changelog

This changelog records verified user-visible repository changes without inventing historical releases.

The project is pre-beta. Version entries should only be added when a release and its date are verifiable.

## Unreleased

### Added

- Structured Engineering Manager execution-plan artifact and semantic validation for downstream planning.
- Managed project runtime updater with ownership checks, conflict refusal, configuration reconciliation, and rollback behavior.
- Release-validation workflow that builds and exercises the exact npm tarball.
- Packaged end-to-end coverage for aico new, aico install, Python bootstrap, user-file preservation, and aico update.
- Public documentation for provider routing, managed ownership/update behavior, security reporting, contribution workflow, and platform/maturity boundaries.
- Persistent TUI language/theme settings, ES/EN switching, Default/Hacker presentation, and updated project/help/planning/work-request screens.

### Changed

- General and writable Auto routing policy is local-first/Ollama-only by default.
- Provider attempts use bounded configured timeouts and remove unusable partial structured output.
- Existing managed projects migrate Auto routing order to current framework policy during runtime update while preserving supported project overrides.
- Public documentation now distinguishes tested environments from unproven platforms and package update from project runtime update.

### Security

- Runtime update refuses unmanaged conflicts and unsafe reparse/path escapes.
- Writable execution remains isolated to registered task worktrees and does not automatically commit, merge, push, deploy, publish, or retrieve secrets.
- Existing-project installation no longer executes a skipped pre-existing `scripts/sync-company-state.ps1`; post-install state sync runs from the package-owned implementation.

## Verified repository history

The current Unreleased summary incorporates changes verified in repository history, including:

- PR #24 — hardening(runtime): bound providers and add safe project upgrades
- PR #25 — feat(planning): add structured engineering execution plans
- PR #26 — hardening(release): validate packaged artifact end to end
- PR #28 — feat(cli): integrate v1.2 hacker TUI with modern runtime
- PR #29 — fix(installer): enforce existing-project sync trust boundary

No new released version or release date is declared by this document.
