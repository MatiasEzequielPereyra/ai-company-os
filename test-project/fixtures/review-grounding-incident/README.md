# Sanitized Review false-approval regression

The primary report is the actual incomplete AICO-002 CTO report from the retained
2026-10-04 headless incident. Its body remains incomplete at the Data Contract
JSON object. The secondary result and legacy approval retain the contradictory
completeness claims. No hidden reasoning is present.

`provenance.json` records relative extraction locators, original raw SHA256,
sanitation policy and sanitized SHA256. Provider/model/timestamp metadata is
removed. Task Objective and Acceptance Criteria are extracted literally; its
metadata is reconstructed at REVIEW for isolated replay, with no historical
dependencies or lifecycle history. Fixtures require no external drive/network.
The directory's Git attributes preserve exact raw bytes on Windows checkouts,
including the JSON serialization's CRLF and the report's captured final space.
Only that report opts out of the trailing-space lint; raw hash checks remain
mandatory, and the engine still normalizes its immutable text view to LF.

Tests never alter historical originals. The negative fake is a concrete semantic
judgment about the truncation; deterministic citation validation does not prove
semantic quality. Genuine irrelevant primary quotes can pass provenance checks.
