# Writable native verification stderr

Windows PowerShell 5.1 can expose native stderr as an error record. With the writable runner's terminating error preference, a warning from a successful native verifier could stop verification before its exit code was evaluated. This rejected an otherwise valid change.

Verification must capture both output streams as evidence and use the native exit code to determine success. Exit zero permits normal result publication and REVIEW transition. A nonzero exit remains fatal and restores the original planned file bytes before any task result is published.

`test-writable-agent-runtime.ps1` now executes two real Node scripts through the actual writable runner and a fake provider router. The first emits stdout and stderr, exits zero, and must retain both markers in evidence while advancing its isolated fixture task to REVIEW. The second emits both streams and exits seven; its fixture task must remain ACTIVE, its product file hash must match the original, and no owner report or task result may exist. Existing traversal, command-composition, primary-checkout preservation, and corrective execution regressions remain in the same test.

Focused validation passed on Windows PowerShell 5.1 using an external temporary directory. The default Windows short TEMP alias exposed a separate fixture worktree-registration path mismatch before verification; the external temporary directory avoids that unrelated harness condition. No acceptance fixture or real provider was used.

Final validation: focused regression also PASS on PowerShell 7; full WinPS smoke/contracts 57/57 PASS; Python 204 PASS; npm 2 PASS. Real headless Run A retry remains pending; no certification is implied.
