# Canonical Acceptance Reference Project v1 — design and verification

Project: AI Company OS
Revision: 2
Updated: 2026-10-03 (UTC)
Updated by: CODEX-ORCHESTRATOR
Base: dd2d6b0d114851d4ef7d55687b530c6fd4ca3e1f
Branch: test/canonical-acceptance-reference-v1
Status: READY_FOR_EXTERNAL_ORCHESTRATOR_RE_REVIEW

## Authorization

The user explicitly requested design, implementation and validation of an independent Python Task CLI reference, isolated worktree/branch, Git-versioned baseline, acceptance contract and a minimal deterministic preflight. Existing Runs #4/#5 and historical dirty checkout are protected. No providers, Run #6, merge, general memory system or scope guard are authorized.

## Product decision

Use a flat two-file `taskcli` package and standard-library argparse. Only `list` exists. Raw stdout is UTF-8 `No tasks.\n` with an LF newline; stderr is empty and exit code 0. Positive baseline tests check the five required observations through independent CLI processes. Packaging metadata declares Python >=3.11 and no runtime dependencies.

A flat package avoids adding build/import configuration to run locally. Optional conventional installation is documented, but no Company OS installation is required to execute this product.

## Contract and preflight

The JSON contract explicitly identifies product/version/root, fixed CLI and baseline-test argv, preserved observable outputs, present capabilities and deliberately missing capabilities. Preflight is specific to v1, uses the active Python executable, and does not execute arbitrary commands taken from mutable metadata. Required sources, actual command behavior, tests, source integrity and missing-feature boundaries are checked. SHA pins normalize source line endings for portability between Git checkouts; CLI output checks remain byte-exact.

Preflight is a baseline-before-E2E check, not a post-feature acceptance gate. It allows extra Company OS framework files in a future copied product but does not confuse them with product capabilities. A reviewed revision or v2 is required for canonical source changes.

## Common Failure Modes: Run #5 lesson

A runtime/framework initialization is not creation of the product to be modified. Requests to extend or preserve existing behavior require existing product sources and observable behavior before E2E. Templates marked UNCONFIRMED do not erase explicit user requirements. Baseline provenance must record product and Company OS runtime separately.

## Validation and preserved state

Final local/CI results, exact source manifest, protected-state comparisons and commit/PR metadata are recorded in this delivery's handoff and external checkpoint. Package/release paths are unchanged: npm's explicit files list excludes acceptance reference projects. No release package changes are necessary.

Final local results: Python reference unittest 5/5 PASS; canonical preflight PASS; preflight regression pytest 10/10 PASS; AI Company OS full Python suite 195/195 PASS. Conventional product install in a fresh temporary copy/venv PASS, including isolated module execution with byte-exact output and no Company OS distribution installed. Runtime npm payload dry-run: 217 entries, zero acceptance entries. No local runtime release E2E rerun is required because runtime/package sources are unchanged; existing GitHub CI results are recorded externally after PR publication.

The first focused regression invocation used default TEMP and hit access errors; a fresh authorized --basetemp resolved them, with final green logs preserved. Runtime Python execution used the bundled Python3.12 executable because unqualified python is unavailable in this process. Source/test commands in the portable contract intentionally use the operator's selected Python >=3.11.

External evidence: Z:/repos/ai-company-os/temp-tests/canonical-acceptance-reference-v1-evidence. Protected-state before/after covers acceptance, both historical harnesses and the dirty checkout. No Run6, Company OS product installation, provider inference, TUI E2E or merge performed.
## PR42 minor review revision

The externally requested taskcli_gitignore_rule capability is now explicitly INTENTIONALLY_MISSING. Preflight requires Git and checks effective ignore semantics in a disposable repository with only the copied product .gitignore, no ambient Git configuration or templates. Either ignored .taskcli/ or .taskcli/tasks.json fails closed with the capability name. Product source, canonical .gitignore and five baseline tests are unchanged.

Verification for this revision: baseline 5/5 PASS; canonical preflight PASS; 19/19 focused preflight regressions PASS; full Python suite 204/204 PASS. Nine added cases cover effective rules (including required .taskcli/ subprocess failure), comments, negations and ambient configuration isolation. Final SHA, GitHub CI and protected Run4/5 evidence are recorded in the successor handoff's external checkpoint.