# Protected source for writable corrective retries

Corrective findings require the actual candidate source to be actionable. The writable runner appends the complete current contents of the union of required source files and changed tracked or untracked files to the protected corrective evidence. Each capture identifies its source path, byte count, SHA-256 of exact bytes and current-candidate provenance. Existing primary checkout contents are comparison evidence for restoring approved scope.

The router budgets this entire source-and-findings envelope. A local provider whose effective budget cannot hold it must be rejected before adapter invocation; permitted fallback preserves the same complete envelope. Generic repository context may be shortened, while authoritative findings and captured source remain complete.

The capture guard deliberately does not treat `max_total_write_bytes` as the size of the evidence envelope. Corrective context contains both candidate source and a primary-project comparison plus required context. Its bounded ceiling is derived from the existing writable and required-context limits and accounts for both views, so a valid small corrective change is not rejected merely because comparison evidence is larger than the write set.

Regressions extend the real writable runner with a changed required source and an untracked Python file, checking exact complete contents and raw-byte hashes in captured corrective context for QA and Security retries. Existing real-router overflow and insufficient-local-budget cases cover preservation and pre-call rejection. No real provider or acceptance fixture is used.
