# Contributing to AI Company OS

AI Company OS is a Windows-first, pre-beta engineering framework. Contributions should keep the repository testable, auditable, and conservative about claims.

## Prerequisites

Current development/CI baseline:

- Git;
- Node.js 20 for the tested npm path;
- npm;
- Python 3.11 or 3.12 for the tested Python path;
- PowerShell;
- optional Ollama/provider credentials only for tests or experiments that actually require them.

Do not put provider credentials in the repository.

## Branch workflow

Work from a branch based on current main.

Keep a change focused. Avoid unrelated refactors, drive-by formatting, mass branch cleanup, or release/version changes unless they are part of the approved scope.

A typical flow:

~~~powershell
git fetch origin
git switch main
git pull --ff-only
git switch -c your-focused-branch
~~~

Use a separate worktree when concurrent work or AI Company OS writable execution requires isolation.

## Setup

Python development environment:

~~~powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
~~~

Install npm dependencies/package metadata as needed:

~~~powershell
npm test
~~~

## Validation

### Full PowerShell smoke suite

~~~powershell
.\test-project\tests\run-all-smoke-tests.ps1
~~~

This is the broadest deterministic repository suite and is used by CI.

### Python

~~~powershell
python -m compileall -q src/company_os
python -m pytest -q
~~~

CI validates Python 3.11 and 3.12 on Windows.

### npm package contract

~~~powershell
npm test
~~~

The package contract checks the declared npm surface.

### Release/package path

Release validation also builds an actual npm tarball and executes the packaged E2E path. Do not weaken or bypass those gates to make a change green.

### Diff hygiene

~~~powershell
git diff --check
git status --short
~~~

Do not commit generated test debris, local runtime caches, virtual environments, provider secrets, or temporary artifacts.

## Coding scope

Preserve established contracts unless the change deliberately updates them with tests and documentation.

Particularly sensitive areas:

- task lifecycle transitions;
- writable authorization;
- worktree isolation;
- protected paths;
- managed-files ownership;
- provider routing/fallback;
- schema/semantic validation;
- release/package contents.

Prefer a small targeted change with a deterministic regression test over a broad rewrite.

## Documentation expectations

If behavior changes, update the public documentation that a new user would rely on.

Documentation follows implementation and tests. Do not document planned behavior as current behavior.

Verify:

- command syntax;
- ownership/update semantics;
- provider routing;
- supported/tested platforms;
- lifecycle states;
- maturity language;
- relative links.

The npm-distributed README intentionally uses absolute GitHub links to the docs tree because the full docs directory is not packaged.

## Pull requests

A useful PR should explain:

- problem and scope;
- implementation approach;
- user-visible behavior changes;
- tests executed with exact results;
- known limitations or follow-ups.

Keep runtime changes and unrelated documentation/repository cleanup out of a focused PR.

## Bugs

Use GitHub Issues for normal bugs and feature requests.

For security-sensitive bugs, follow SECURITY.md and do not publish exploitable details or secrets in a public issue.
