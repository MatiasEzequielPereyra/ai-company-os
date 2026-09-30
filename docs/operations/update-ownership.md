# Update and Ownership

AI Company OS separates **package installation**, **project installation**, and **managed runtime update**.

This distinction is part of the safety model.

## Three different operations

### Global package update

~~~powershell
npm install -g @pereyram/ai-company-os@latest
~~~

This changes the globally installed npm package.

It does not rewrite projects that already contain AI Company OS files.

### Install into a project

~~~powershell
aico install .
~~~

This installs the framework surface into an existing directory.

Normal installation skips existing framework-path files instead of overwriting them silently.

The optional force mode exists for explicit reinstall scenarios. It can replace existing framework-path files and is **not** the supported substitute for project runtime update.

### Update a managed project runtime

~~~powershell
aico update .
~~~

This invokes the package-owned updater against an already managed project.

## The ownership manifest

The contract is:

~~~text
.codex/managed-files.json
~~~

Current schema version: 1.

The manifest records paths claimed by AI Company OS installation/scaffolding. The updater refuses to guess ownership when:

- the manifest is missing;
- its JSON is invalid;
- its version is unsupported;
- it does not claim its own manifest;
- it does not contain a recognizable managed runtime contract.

This fail-closed behavior is intentional.

## What aico update currently updates

The current updater owns a narrower runtime namespace than the full installation surface.

Direct runtime replacement/addition/removal includes:

~~~text
scripts/*.ps1
scripts/providers/*
scripts/local-runtime/*
schemas/*.schema.json
~~~

It also merges these managed configuration files:

~~~text
.codex/provider-config.json
.codex/local-runtime-config.json
.codex/writable-policy.json
.codex/workflow-profiles.json
~~~

The updater migrates general and writable Auto routing order to current framework policy so stale automatic cloud fallback semantics do not survive an upgrade.

Other compatible project overrides are preserved when the merge contract allows it.

## What it deliberately preserves

The updater explicitly does not mutate normal project source, tasks, Work Requests, project documentation, gate evidence or project state as part of runtime update.

It also does not currently promise to evolve every installation-time asset, including all:

- agents;
- policies;
- protocols;
- workflows;
- templates;
- skills.

Those assets may exist in the managed-files manifest because installation created them, but the current updater's mutation namespace is deliberately smaller.

This is a current product limitation, not an invitation to copy files over a project manually.

## Conflict handling

Before applying changes, the updater checks target paths.

If a runtime/config path already exists but is not recorded as managed, update aborts instead of overwriting it.

The updater also rejects unsafe relative paths and symlink/junction/reparse-point escapes.

## Transaction-like application

The updater:

1. preflights ownership and paths;
2. precomputes merged configuration;
3. creates temporary backups of affected existing files;
4. applies runtime/config changes;
5. removes deprecated managed runtime files;
6. rewrites the managed manifest;
7. attempts rollback if application fails;
8. removes its temporary backup area.

This is safer than a forced reinstall, but it is still sensible to run updates on a clean Git branch and inspect the resulting diff.

## Legacy/unmanaged projects

If an old project does not have a valid managed-files contract, aico update refuses to proceed.

Do not solve that by telling the updater to guess, and do not automatically replace the project with a forced install.

Treat legacy migration as a separate owner-reviewed operation. Back up the repository, inspect which framework files are project-modified, and decide how to establish a supported ownership contract.

## Package-owned updater

**scripts/update-runtime.ps1** is executed from the installed npm package. It is not materialized into client projects by the current runtime updater contract.

That keeps the update mechanism anchored to the package version being installed.

## Active project selection

Running aico update against a target does not change the user's active-project selection as an unrelated side effect.

## Post-update checks

~~~powershell
aico version
aico doctor --system
aico doctor
aico status
git status --short
~~~

Review any changed managed configuration before continuing work.

## Tested evidence

Current release/package validation exercises the exact npm tarball and verifies:

- packaged aico new;
- packaged aico install;
- package-local Python bootstrap;
- preservation of a pre-existing user-owned file;
- valid managed runtime artifacts;
- packaged aico update;
- restoration of a stale managed runtime file from the installed package;
- preservation of a user-owned file through update.

The dedicated update contract also checks fail-closed ownership and configuration migration behavior.
