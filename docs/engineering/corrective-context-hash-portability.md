# Corrective context hash portability

Project: AI Company OS
Revision: 1
Updated: 2026-10-04
Updated by: PRINCIPAL RUNTIME / E2E ENGINEER
Base: 7e9471c6dfb7c55d8389b282ac9fdaa99d04d7e8 (PR44)

A real headless PM corrective retry failed before provider selection in `Compact-TicketHistory`: `Get-FileHash` was unavailable. Task AICO-001 remained ACTIVE. Review CHANGES_REQUIRED and the previous owner result remained intact. The new diagnostic fixture was created from the canonical public Python Task CLI V1; historical runs were untouched.

The parent PowerShell 7 process supplied Core-first PSModulePath to Python, which launched Windows PowerShell 5.1. ConvertFrom-Json loaded Microsoft.PowerShell.Utility 7.0.0.0 from the bundled Core modules; Get-FileHash then could not resolve. Direct PowerShell launches sanitize that path and use Utility 3.1.0.0, explaining the gap in direct smoke coverage. A minimal non-provider probe reproduced the same failure without diagnostic transport tracing. The TUI's ProviderService preserves this environment and AgentControlService prefers powershell.exe, so the path is reachable in normal runtime execution.

The corrective context builder now computes SHA-256 over exact file bytes using a .NET file stream. It disposes the stream and hash algorithm in finally. The lower-case digest, compaction markers, evidence selection, protected findings and provider budgets remain unchanged. No lifecycle or provider semantics changed.

Regression coverage makes Get-FileHash unusable and asserts the complete corrective envelope, exact UTF-8/BOM/Unicode/CRLF byte digest, retained latest findings and budget. Focused regression and the full 54-suite Windows PowerShell smoke passed. Real provider execution is stopped while this correction is verified.

Evidence: Z:/repos/ai-company-os/temp-tests/headless-runtime-e2e-2026-10-04, particularly run-a/02-pm-corrective-01 and fix-01/full-powershell.log. This fix is stacked on PR44; neither PR is merged by this task.

Authorization: the user's headless E2E request explicitly permits an isolated fix and regression after the first deterministic engine defect, followed by a legitimate runtime update and retry at the appropriate point. It prohibits manual lifecycle edits, historical acceptance changes, Codex provider and intentional paid calls.
