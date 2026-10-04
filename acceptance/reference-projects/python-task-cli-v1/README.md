# Python Task CLI — reference v1

An independent, deliberately minimal Python product. It currently lists an empty set of tasks. It does not use AI Company OS, external services, or third-party runtime dependencies.

Requires Python 3.11 or newer. Run these commands from this directory.

## Run

No installation is needed:

```text
python -B -m taskcli list
```

Optional conventional installation into your own virtual environment:

```text
python -m pip install .
```

After installation the same module command works outside this directory.

## Empty-list contract

Command: `python -B -m taskcli list`.

- stdout: exactly `No tasks.\n` (UTF-8 bytes, one LF newline).
- stderr: empty.
- exit code: `0`.

`python -B -m taskcli --help` describes the current command. `list` accepts no additional arguments.

## Tests

The five positive baseline tests check CLI execution, the existing list command, stdout, stderr and exit status:

```text
python -B -m unittest discover -s tests -v
```

The baseline contract and source are checked separately with:

```text
python -B preflight.py
```

Preflight uses Python standard-library code and requires Git. It runs the actual CLI and baseline tests, and rejects missing files, inconsistent metadata or drift in the v1 source. Its negative checks verify that the deliberately absent capabilities were not introduced. Git evaluates the copied `.gitignore` in a temporary isolated repository; an effective ignore rule for `.taskcli` or its task data advances the deliberately absent `taskcli_gitignore_rule` capability and fails preflight. Comments and effective negations follow Git semantics; user/global excludes do not affect this check. It uses temporary storage outside this product and leaves no runtime artifacts here. A successful run prints JSON with `status: PASS`, `project_id: python-task-cli-v1`, the five baseline tests and zero provider calls.

## Current limitations

Only listing an empty set is implemented. There is no add, complete or remove command, task storage, persistent numeric IDs, or completed/pending persistence. `.taskcli/tasks.json` and `TASKCLI_DATA_FILE` are not implemented. The current `.gitignore` covers Python development artifacts; it deliberately does not ignore `.taskcli/`.

`acceptance-project.json` records present capabilities, `INTENTIONALLY_MISSING` capabilities, preserved behavior and the preflight expectations. It describes this baseline, not functionality developed later.

## Canonical baseline

Acceptance Runs must never work directly in or modify this canonical reference directory. Use a fresh copy with recorded Git baseline provenance. Future changes to the canonical baseline require a deliberate v2 or an explicitly reviewed revision; historical runs must retain their original baseline.

The v1 preflight is a before-E2E baseline check. Once a run implements the deliberately missing capabilities, it is no longer a v1 baseline; this preflight is not the post-implementation acceptance gate.
