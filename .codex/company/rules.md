# Company Rules

These rules apply to every agent.

---

## 1. Understand Before Acting

Agents must inspect the relevant project context before making changes.

Do not make assumptions when the required information can be obtained from the repository or another agent.

---

## 2. No Invented Requirements

Agents must not invent product requirements.

If requirements are ambiguous:

1. Identify the ambiguity.
2. Ask the appropriate owner.
3. Continue only when the ambiguity does not affect the implementation.

---

## 3. Respect Ownership

Each agent has a defined area of responsibility.

Agents must not silently override another department's decisions.

---

## 4. Architecture

Existing architectural decisions must be respected.

If implementation requires changing architecture:

1. Identify the problem.
2. Propose the change.
3. Escalate to the CTO.
4. Document the decision.

---

## 5. Small, Focused Changes

Agents should modify only files relevant to the assigned task.

Avoid unrelated refactors.

---

## 6. Verification

No agent may declare work complete without verification.

Verification may include:

- Unit tests
- Integration tests
- End-to-end tests
- Static analysis
- Linting
- Type checking
- Manual verification

Use the appropriate verification for the task.

---

## 7. Documentation

Important decisions must be documented.

Architecture decisions belong in:

docs/decisions/

Technical documentation belongs in:

docs/architecture/

Engineering conventions belong in:

docs/engineering/

---

## 8. Communication

Agents must communicate through explicit artifacts whenever possible.

Examples:

- Tasks
- Plans
- Handoffs
- ADRs
- Review reports

Do not rely on undocumented assumptions.

---

## 9. Blockers

If blocked, an agent must:

1. Describe the blocker.
2. Explain why it cannot proceed.
3. Identify what information or action is required.
4. Escalate to the appropriate owner.

Never silently guess when the decision has meaningful consequences.

---

## 10. Security

Security-sensitive changes require additional review.

Never expose:

- Secrets
- API keys
- Credentials
- Tokens
- Private user data

Never commit secrets to the repository.

---

## 11. Production Safety

Production-impacting actions require explicit validation.

Agents must not assume that a deployment is safe simply because tests pass.

---

## 12. Definition of Done

A task is not DONE until:

- Requirements are satisfied.
- Implementation is complete.
- Relevant tests pass.
- Relevant checks pass.
- Documentation is updated when necessary.
- No known critical blocker remains.