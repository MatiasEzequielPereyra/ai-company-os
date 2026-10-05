# Python writable source context

An implementation request can create a missing module and update an existing module in the same sentence. Required-file resolution must inspect each positive write clause: the missing create target has no current content, while the later update target must enter the context with its exact current contents. Reference material after `using` or `via` must not become an additional write target merely because it describes an example modification.

Python source and tests also belong in the general repository context. Including `.py` uses the existing inventory, ranking, context budgets, and exclusions for secrets, vendor directories, managed runtime files, and oversized files. It does not grant writable authorization or create missing files.

`test-python-writable-source-context.ps1` constructs an isolated Python baseline, resolves a compound Create/Update request, checks narrative reference exclusion, and sends the real context builder output through the real provider router to a fake OpenRouter adapter. The capture must contain the complete current `__main__.py` and Python baseline test. No real provider or acceptance fixture is involved. Existing writable resolution, authorization, and budget tests remain part of smoke coverage.
# Validation checkpoint

Windows PowerShell 5.1 focused context regressions: 4/4 PASS.
Full PowerShell smoke/contracts: 57/57 PASS.
Full Python suite: 204 PASS. npm tests: 2 PASS.
Real headless E2E remains pending retry; these results do not certify it.
