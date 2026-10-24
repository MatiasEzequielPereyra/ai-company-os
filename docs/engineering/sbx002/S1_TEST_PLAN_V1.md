# S1 deterministic verification plan V1

Project: AI_COMPANY_OS
Revision: 1
Task: SBX002_S1_PURE_CORE_IMPLEMENTATION_V1
Base: 12439870d44ead5b538c2ecd33f776ebc15efe12
Status: PLANNED_NOT_EXECUTED

All data is synthetic. No tests call a real provider, broker, VM, VSS, IPC or
operational sandbox. Normal repository test runners are authorized development
processes, not sandbox execution. Existing mocked TUI tests remain included.

## Independent oracles

- Use literal expected mapping rows from historical A/B/C/D; do not compute an
  expected result by calling the reducer under test.
- Enumerate lifecycle/result/resource combinations and reject impossible states.
  Assert expected invariants on every admitted transition and exact representative
  outputs for each row, including terminal-first B and residual D20.
- Pair every retry guard with its independently negative input; distinguish
  confirmed no-code from uncertain submission. Require exact accumulated deadlines.
- Use literal scheduler orders for Start/invalidate/result/seal/publish, including
  repeated, stale and foreign-epoch events. A fake committed intent is data, never
  an assertion of durable disk state.
- Build independent raw JSON fixtures and digests. Exercise every supported new
  piece and both package variants, matching V1 through existing validators.
- Check mutations at every nested closed shape, identity/digest binding and size
  boundary. Assert byte preservation; duplicate JSON keys must fail before dict
  conversion. No parser claims semantic authority from valid data.

## Negative families

Invalid UTF-8/BOM/escape/depth, duplicate/unknown/missing keys, nonfinite/float/bool
integers, invalid UUID/hash/time/version, excessive pieces/items/events/bytes,
unreferenced/duplicate/cyclic references, absent fields, cleanup/monitor UNPROVEN,
fake PolicyApproval, OPERATIONAL claim on a simulation, failure to keep invalidation
latched, uncertain commit/journal, restart, retry consumed, budget n/n+1 and clock
discontinuity. No exception or unknown enum becomes successful evidence.

## Required delivery evidence

Record exact source commit, runtime versions, focused tests, full SBX-001 tests,
full Python suites where available, applicable official CI and package validation.
Preserve failures as failures. No automatic changes to unrelated tests, skip/xfail,
assertion deletion or product runtime fixes. Independent code/security review
must close P0/P1 before publication. Draft PR and B audit remain distinct from
merge authorization and operational certification. P0 remains OPEN.
