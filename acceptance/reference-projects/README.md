# Canonical acceptance reference projects

## Python Task CLI v1

[python-task-cli-v1](python-task-cli-v1/README.md) is the independent product used to establish real existing behavior for a future task-persistence acceptance request. Its machine-readable contract is [acceptance-project.json](python-task-cli-v1/acceptance-project.json).

The product currently supports only `list`, which emits exactly `No tasks.\n`, no stderr, exit 0. Its CLI, five positive tests and specific preflight run without installing Company OS or calling providers.

## Immutable run provenance

Acceptance Runs never modify the canonical reference project. Changes require an explicit v2 or a reviewed baseline revision; do not retroactively change a baseline used by historical runs.

The future authorized setup sequence is:

1. Select the approved repository commit and reference contract version; record source hashes.
2. Copy only this reference product into a new, previously absent run directory. Do not copy `.git`, Python caches, environments or build artifacts.
3. Create and record the fresh product's Git baseline.
4. Install the approved Company OS package into the fresh product using its canonical existing-project operation. Preserve product code, tests, README, pyproject and acceptance contract; record the installed runtime provenance separately.
5. Run this product's baseline preflight from the fresh copy and verify the copied product still matches the approved contract. Framework files are not evidence of product capabilities.
6. Obtain the required external setup approval before the user begins the manual TUI E2E.

The reference contract's `root` is relative to its own directory. Commands run there and use the selected Python executable. No absolute developer paths or global Company OS installation are part of this product.

## Learning from Run #5

Run #5 was initialized with Company OS alone. Its baseline contained 118 managed framework files and no Python product, source directory, product tests or usage README. The request nevertheless required extending an existing Python task CLI and preserving its empty-list behavior. The explicit requirements survived, but the product precondition did not exist.

Any acceptance request that says extend/preserve an existing product requires that product and its observable baseline before E2E. This reference materializes that prerequisite with actual code, tests and a preflight. It does not implement a general learning system or change historical incident evidence.

## Scope of this delivery

No Run #6 is created or configured. No providers, Company OS functional workflow, persistence implementation or merge are included. Baseline preflight checks must not be mistaken for approval of future product functionality.
