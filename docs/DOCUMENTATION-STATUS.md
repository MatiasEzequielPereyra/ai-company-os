# AI Company OS — Documentation Status

Status: **pre-beta living documentation / re-audit candidate**

This file distinguishes what is documented and validated from what remains limited or unproven.

## Documented and validated

| Area | Current evidence |
| --- | --- |
| npm package identity and CLI entrypoint | package.json and package tests |
| Python runtime requirement | pyproject.toml and Python CI |
| aico new | packaged npm E2E |
| aico install | packaged npm E2E plus install contract |
| package-local Python bootstrap | packaged npm E2E |
| aico update | update contract plus packaged npm E2E |
| managed-files fail-closed update | update-runtime contract |
| project-owned file preservation in packaged flows | npm E2E |
| skipped project-owned sync script remains unexecuted during install | install contract plus packaged npm E2E |
| persistent ES/EN language and Default/Hacker TUI themes | interface settings/theme tests plus TUI integration |
| general Auto = Ollama by default | provider config/router/update contract |
| Engineering Manager analysis override | provider config/router |
| writable Auto/local-first safety | writable runtime and policy |
| task lifecycle and transition guards | protocol and smoke tests |
| Review/QA/Security/final approval | gate scripts and smoke tests |
| structured Engineering Manager planning | schema, semantic validator and planning tests |
| writable worktree isolation | writable protocol and smoke tests |
| Windows CI | windows-latest workflows |
| Python 3.11 and 3.12 | Python CI matrix |
| Node 20 release/package path | smoke/release workflows |

## Documented but limited

### Windows support

Windows is the primary target and current GitHub Actions evidence runs on windows-latest.

The repository does not currently claim a separately validated Windows 10 client matrix or Windows 11 client matrix.

### Node versions

package.json declares Node >=20. CI currently proves Node 20, not every later Node major.

### Python versions

pyproject.toml declares Python >=3.11. CI currently proves Python 3.11 and 3.12.

### Providers

Provider adapters and deterministic contracts are tested. This does not prove live availability, account quota, pricing, or model behavior for every external provider.

### Writable execution

The runtime can apply validated change sets in isolated registered worktrees. Commit, merge, rebase, push, deployment, release and publication remain separate authorized actions.

### Project update

aico update evolves the current runtime namespace and selected managed configs. It does not currently update every installation-time framework asset such as all agents, policies, protocols, workflows, templates or skills.

## Known product/documentation gaps

### Review independence for Engineering Manager-owned tasks

The Review gate currently assigns the Engineering Manager role as reviewer. Therefore an Engineering Manager-owned task is not guaranteed role-level reviewer independence.

Documentation does not claim otherwise. Changing reviewer policy is a product/architecture decision, not a documentation fix.

### Wrapper command-specific help

The npm launcher handles new, install/init and update before handing off to the Typer CLI. These wrapper commands do not currently provide the same command-specific help surface as Typer subcommands.

The command reference is the authoritative syntax reference for them.

### Legacy unmanaged project migration

Projects without a valid managed-files ownership contract cannot use aico update. A safe automatic legacy migration workflow is not currently established.

### Security private-reporting configuration

No project-specific security email or private-reporting SLA is documented. SECURITY.md tells reporters to use GitHub private vulnerability reporting when the repository UI exposes it and otherwise request a private channel without publishing sensitive details.

## Platform limitations

Not established as supported by current CI:

- Linux;
- macOS;
- specific Windows 10 client matrix;
- specific Windows 11 client matrix.

Code paths that appear portable are not equivalent to tested support.

## Release limitations

The repository has strong release-candidate validation but this documentation does not label the project production-ready.

No release version is created by this documentation work.

## Intentionally not documented as supported

- fully autonomous software company operation;
- automatic cloud fallback from general Auto;
- automatic paid provider fallback;
- automatic merge/push/deploy/release;
- unrestricted repository mutation;
- automatic secret retrieval;
- full cross-platform support;
- automatic migration of every legacy installation;
- updating every framework asset in an existing project via aico update.

## Documentation consistency

Public documentation should be checked for:

- broken repository-relative links;
- stale known Auto fallback claims;
- hardcoded developer-local paths;
- force-install-as-updater guidance;
- missing public command names.

The repository contains a deterministic documentation-contract test for these invariants.
