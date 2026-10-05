# Writable Git inventory stderr

Git can emit an LF/CRLF conversion warning while returning exit zero. Windows PowerShell 5.1 exposes that native stderr as an error record. The writable runner's terminating error preference therefore rejected valid implementations during changed-path inventory after verification had already passed. The same warning also occurred during the subsequent patch evidence capture.

Changed-path inventory must use stdout paths only, tolerate nonfatal stderr within the native capture scope, and explicitly check each native exit code. Real Git failures remain fatal; a failed inventory must never appear as an empty clean worktree. Capture scopes restore the caller's PowerShell and native error preferences.

The existing writable runtime regression now creates a real Git repository with `core.autocrlf=true`, commits a CRLF baseline, and applies a tracked LF change plus a new untracked product file through the actual writable runner and a fake provider router. It independently confirms the real Git LF/CRLF warning and zero exit code, requires REVIEW, and checks that the complete inventory contains exactly the tracked and untracked paths without warning text. A non-repository path must throw and preserve error preferences. Existing real Python unittest and native stderr regressions remain active.

No acceptance fixture or real provider is used. Focused execution uses an external temporary directory and adds the bundled Python folder to PATH only for that test process.

Final validation: focused PASS on WinPS5.1 and PS7; full WinPS smoke/contracts 57/57 PASS; Python 204 PASS; npm 2 PASS. All six captured Git reads use the helper; existing failure messages and exit-code rejection remain. Actual headless retry remains pending.
