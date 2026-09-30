# Security Policy

AI Company OS is pre-beta software and executes or coordinates tooling that can inspect repositories and, in explicitly authorized flows, apply source changes inside isolated Git worktrees.

Security reports are welcome. Do not include secrets, provider keys, access tokens, private repository contents, or weaponized exploit details in a public issue.

## Reporting a vulnerability

This repository does not currently document a project-specific security email or SLA.

If GitHub shows **Report a vulnerability** / private vulnerability reporting for this repository, use that private GitHub channel.

If no private reporting channel is available in the repository UI, open a minimal public GitHub issue stating that you need a private security-reporting path. Do **not** include sensitive technical details in that issue. Repository maintainers should then establish a private channel before details are shared.

Normal bugs that are not security-sensitive can use GitHub Issues.

## What to include privately

When a private reporting path is available, include:

- affected version/commit;
- affected component or command;
- prerequisites;
- minimal reproduction steps;
- expected versus observed behavior;
- security impact;
- whether credentials, filesystem writes, worktrees, provider output, or update ownership are involved;
- suggested mitigation if known.

Do not send real secrets as proof.

## Scope

Security-relevant areas include:

- writable execution and path containment;
- Git worktree/branch isolation;
- managed runtime update ownership;
- provider credential handling;
- provider output validation;
- structured change-set validation;
- protected paths and secret-name filtering;
- verification-command parsing;
- artifact/state integrity;
- dependency and lifecycle authorization boundaries.

## Credentials

Provider credentials are expected through external provider authentication or environment variables such as:

~~~text
OPENROUTER_API_KEY
GEMINI_API_KEY
DEEPSEEK_API_KEY
XAI_API_KEY
~~~

Codex CLI uses its own configured authentication/session.

Never commit provider keys, .env secrets, private keys, service-account files, or credentials into a project so AI Company OS can find them.

The writable policy treats common secret-bearing path patterns as prohibited targets. That defense is not a substitute for normal secret management.

## Writable execution boundary

Writable execution is restricted to a registered task-specific Git worktree and expected task branch. The runtime rejects protected control-plane paths, path traversal, unsafe absolute paths, and reparse-point escapes.

Writable execution does not automatically commit, merge, rebase, push, deploy, publish, or retrieve secrets.

These boundaries reduce risk; they are not a guarantee that generated code is secure. Review and applicable QA/security gates remain required.

## Managed update boundary

aico update requires the managed-files ownership contract and refuses unmanaged conflicts rather than overwriting them. The updater also rejects unsafe paths and attempts rollback on application failure.

## Supported versions

There is not yet a multi-version security-support matrix. The repository is pre-beta and documentation tracks current main plus the current npm package contract.

When reporting a vulnerability, include the exact package version and commit when possible.

## Response expectations

No response-time or remediation SLA is currently promised. Maintainers should acknowledge and triage valid reports as capacity allows, avoid exposing reporter-provided sensitive information, and coordinate disclosure after a fix or mitigation is understood.
