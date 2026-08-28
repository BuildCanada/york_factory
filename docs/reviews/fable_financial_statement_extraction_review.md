# Fable review: financial statement extraction simplification

Review date: 2026-08-27
Review session: `ontology-fable-ocr-review-20260827`
Reviewer: Claude Fable 5, high effort, read-only repository and legacy-pipeline review

## Verdict

The original OCR specification was an archival-transcription design applied to a headline-fact
problem. Fable recommended reducing the first release to nine PSAS totals with immutable source
identity, physical-page and verbatim-value provenance, strict current-year column selection, and
deterministic accounting checks.

## Principal changes accepted

- Two extraction/fact tables replace page, OCR-token, table-cell, section, and verification
  artifact tables.
- Source provenance is `(document ID, asset SHA-256, page, raw label, raw number)`.
- The page locator sends only primary-statement pages to the model, allowing very large annual
  reports to be processed safely.
- The parser and validator are bilingual, including French number formats.
- PSAS identities replace corporate balance-sheet assumptions and multi-pass OCR voting.
- Only the source document's own fiscal-year actual column is extracted.
- Schema failures and accounting-identity failures block acceptance.

## Important cautions

- Municipal statements often do not print a corporate-style `total assets`; preserve the actual
  PSAS concepts and never manufacture the missing total.
- The legacy First Nations pipeline used nondeterministic model calls, sometimes retained raw
  schema-invalid output, and had incomplete French validation. None of those behaviours should be
  carried forward.
- Existing ontology release records are append-only. Extracted facts must reference stable
  canonical IDs and source hashes rather than becoming release-scoped children.
- Full archival OCR can be added later without invalidating page-and-verbatim fact provenance.
