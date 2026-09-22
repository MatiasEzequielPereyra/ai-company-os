# AI Company OS Test Suite

This directory contains reproducible validation scenarios for AI Company OS.

## Automated smoke tests

Run from the repository root:

```powershell
.\test-project\tests\test-project-intake.ps1
```

The intake smoke test creates an isolated temporary Node/Vite/React/Supabase fixture, runs `initialize-project.ps1`, validates the generated durable context, and deletes the fixture.

## Validation areas

- Project initialization and intake
- Configuration and agent loading
- Product and architecture delegation
- Engineering task delegation
- Review, QA and security gates
- End-to-end execution
