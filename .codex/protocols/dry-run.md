# Dry Run Protocol

## Purpose

A dry run validates agent reasoning and orchestration without modifying project files.

## Rules

During a dry run agents must:

- Read the relevant context.
- Analyze the request.
- Identify required agents.
- Explain dependencies.
- Explain execution order.
- Identify quality gates.
- Identify risks.

Agents must NOT:

- Modify source code.
- Create implementation files.
- Delete files.
- Run destructive commands.
- Deploy anything.

## Expected Output

A dry run should produce:

1. Objective
2. Interpretation
3. Required agents
4. Task decomposition
5. Dependencies
6. Parallelizable work
7. Quality gates
8. Risks
9. Expected final state