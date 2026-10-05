# Writable Python unittest verification

Python's standard-library unittest verifier was missing from the writable verification policy despite being the baseline project's documented verification command. A second independent restriction appeared after adding the policy rule: PowerShell parses single-dash arguments such as `-B`, `-m`, `-s`, and `-v` as command parameters, while the safe-command parser previously accepted only string expressions. The approved verifier therefore could not reach native execution.

The policy authorizes `python -m unittest` with an optional `-B` flag. The parser preserves standalone literal flags as argv entries; it continues rejecting attached expressions, shell composition, pipelines, absolute paths, traversal, and arbitrary `python -c` execution.

The existing writable runtime regression now invokes real Python standard-library unittest through the actual writable runner and a fake provider router. `python -B -m unittest discover -s tests -v` runs one passing test, preserves its output in evidence, and advances the isolated fixture task to REVIEW. A failing test exits one, restores the exact original product file hash, leaves its task ACTIVE, and publishes no task result. Nine adversarial command cases preserve the command safety boundary, including substitution and an attached environment expression.

Focused Windows PowerShell 5.1 validation passed. The bundled Python executable is added to PATH only within the disposable test scope and the prior PATH is restored afterward. No real provider or acceptance fixture is used.
# Final validation

WinPS5.1 and PS7 focused writable runtime regressions PASS, including real
stdlib unittest success/failure and nine rejected adversarial commands.
Full PowerShell smoke/contracts 57/57 PASS; Python 204 PASS; npm 2 PASS.
The test locates Python through PATH and has no user-specific runtime location.
The real E2E retry remains pending; no certification is implied.
