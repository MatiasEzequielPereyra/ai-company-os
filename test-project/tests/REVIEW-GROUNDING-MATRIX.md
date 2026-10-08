# Review grounding v1 regression map

Ordered A–Z execution: Windows PowerShell 5.1 and PowerShell 7 each PASS
`test-review-grounding-primitives.ps1` (29 assertions),
`test-review-grounding-evidence.ps1` (58),
`test-review-grounding-real-incident.ps1` (15), and
`test-review-grounding-materialization.ps1` (22),
`test-review-grounding-intake-preservation.ps1` (18), and coordinator
`test-review-grounding-router.ps1` (28): **170 per runtime** across these six.
The coordinator also passed writer/maintenance locks, actual Review intake and
implementation-candidate coverage in both shells: ten scripts per runtime.
The final Windows PowerShell smoke run passed 66/66 scripts with TEMP/TMP
canonicalized to their long Windows paths. Validation follows focused → existing
relevant → incident → complete A–Z → packaging → full PS → Python → release.

| Case | Explicit executable coverage |
|---|---|
| A Complete valid approval | evidence: registered positive token/full eight IDs; migrated test-review-engine: actual APPROVE intake to QA |
| B False summary as evidence | evidence authority rejection; real-incident secondary-only adaptation rejected |
| C Fabricated locator | evidence zero/reversed/oversized/noninteger ranges rejected |
| D Altered quote | evidence trailing space/case/material differences rejected |
| E Wrong task/path/artifact | evidence unknown primary/other task/provider URL lookup rejected |
| F Raw drift | evidence LF→CRLF rewrite invalidates final intake despite unchanged text |
| G LF/CRLF/BOM | evidence independent captures normalize equally, raw hashes differ, cross-snapshot substitution rejected |
| H Duplicate text | evidence line6 accepted; quote relocated to line5 rejected |
| I Primary/result contradiction | real-incident original incomplete primary vs false complete secondary; no secondary authority |
| J Truthful changes | real-incident actual REVIEW→READY; evidence negative can cite no invented positive proof; intake-preservation generic prose retains structured missing/defect/UNSAT rationale through canonical Markdown and actual corrective context |
| K Legacy approval | real-incident original message.content replay rejected at helper and actual intake |
| L Coverage shrinkage | evidence missing, duplicate, unknown IDs rejected |
| M Repair/fallback snapshot | coordinator test-review-grounding-router: actual router fake adapters, immutable context |
| N Exhausted invalid providers | coordinator test-review-grounding-router: no canonical approval/transition, retained rejection |
| O Limits | evidence 65 obligations, >3 references, 2049-byte real line and >32KiB aggregate reject; coordinator router protected-budget preflight |
| P Unicode/whitespace | primitives astral/combining/tabs/trailing LF/loneCR; evidence genuine quote accepted, NFC change rejected |
| Q Source security | evidence unauthorized relative/UNC/drive/secret declarations reject before access; TaskPath escape; real directory-junction source rejected. Intake-preservation rejects destination junction before outside/project writes. Existing implementation-gate-candidate-context tests registered workspace, secret, limits and literal reparse ancestors |
| R Conditional ADR | evidence exact ordinal7 declaration+conditional_authority accepted; unconditional waiver rejected |
| S Semantic boundary | evidence genuine irrelevant primary quote deliberately passes provenance; no claim of deterministic semantic quality |
| T Source/declaration drift | evidence changed/deleted primary; router same snapshot on repair; primitives malformed declaration fences |
| U Unsupported declaration | primitives nine malformed shapes; evidence nested declaration rejects entire NewContext preparation |
| V Ownership/race | task-writer-lock-contract including canonical full-path/Windows TEMP short-alias live ownership; project-maintenance-barrier; real-incident exact same task and project live handles through nested intake/update/advance |
| W Generated QA | materialization real engine objective criterion, five IDs, zero role outputs; generic-only control fails |
| X Generated Security | same materialization test literal security objective and exact ordinary ID |
| Y Generated DevOps | same materialization test literal deployment objective and exact ordinary ID |
| Z Unsupported planning role | materialization qa+backend mixed batch rejected before task writes; prior task bytes and mapping preserved |

The junction regression requires host permission to create a junction in its
owned disposable temporary directory. It fails visibly when that permission is
unavailable; it is never silently skipped. All provider behavior is fake. No
historical evidence, source task, real provider or user configuration is mutated.

Packaging assertions: new-project-contract and npm-package-contract explicitly
check grounding helper, Review schema and execution helper inventory and exact
source bytes, then exercise the shipped project shared/exclusive barrier. The
release npm-package-e2e checks manifest ownership and source hashes after actual
`aico new`, `aico install` and `aico update`; it first introduces managed drift
in all three artifacts, so update must restore actual package bytes. Coordinator
runs E2E against its final tarball. Targeted WinPS probes pass both contract
tests; PS7 npm contract passes. PS7 generated-project validation separately fails
at the existing timestamp/schema boundary (`$.generated must be a string`), after
the added grounding/barrier assertions; it is not reported as a complete PASS.
