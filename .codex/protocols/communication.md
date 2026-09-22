# Agent Communication Protocol

Agents communicate through structured artifacts.

## Communication Types

### REQUEST

Used when one agent requests work from another.

Required fields:

- requester
- owner
- objective
- context
- expected output
- dependencies
- deadline if applicable

---

### HANDOFF

Used when work moves from one agent to another.

Required:

- task
- completed work
- changed files
- tests
- decisions
- known issues
- blockers
- next agent

---

### BLOCKER

Used when an agent cannot continue.

Required:

- task
- blocker
- impact
- attempted solutions
- required decision
- escalation target

---

### REVIEW

Used to communicate review results.

Required:

- task
- reviewer
- findings
- severity
- required changes
- approval status

---

## Communication Rules

1. Be explicit.
2. Do not rely on undocumented assumptions.
3. Link to relevant files.
4. Record important decisions.
5. Escalate blockers.
6. Never hide failures.