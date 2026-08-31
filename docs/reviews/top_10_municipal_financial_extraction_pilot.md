# Top-ten municipal financial extraction pilot

Date: 2026-08-27

Extractor: `headline-psas-v1`

Model: `gemini-3-flash-preview`

## Outcome

The final implementation passed all hard gates for all ten municipalities. It extracted 90 facts, and the deterministic number parser reproduced all 90 stored whole-dollar values exactly from each fact's cited raw text and scale. No pilot PDF required OCR; the bounded OCR fallback remains available for image-only pages.

| Municipality | Fiscal year | Position page | Operations page | Facts | Identity exceptions supported by page text |
|---|---:|---:|---:|---:|---|
| Toronto | 2023 | 5 | 6 | 9 | Separate remeasurement balance |
| Montréal | 2022 | 25 | 26 | 9 | None |
| Calgary | 2025 | 42 | 43 | 9 | Remeasurement; other capital contributions/transfers |
| Ottawa | 2024 | 43 | 44 | 9 | Remeasurement; surplus roll-forward adjustment |
| Edmonton | 2025 | 6 | 7 | 9 | Remeasurement; other operating items; surplus roll-forward adjustment |
| Winnipeg | 2025 | 70 | 71 | 9 | Other contributions/transfers |
| Mississauga | 2025 | 7 | 8 | 9 | Separate remeasurement balance |
| Vancouver | 2025 | 17 | 18 | 9 | None |
| Brampton | 2018 | 17 | 18 | 9 | None |
| Hamilton | 2022 | 16 | 17 | 9 | Other comprehensive income in the surplus roll-forward |

Montréal uses the complete official 2022 annual financial report because the current Constellio viewer could not be downloaded reproducibly. Brampton and Hamilton use the newest correctly identified complete municipal statements in the existing archive; newer locally indexed files were incomplete or belonged to another issuer.

## Iterations driven by the pilot

1. Toronto exposed a tenfold model normalization error even though its copied raw number was correct. The redundant model-supplied normalized value was removed; normalization is now always deterministic.
2. Montréal exposed encrypted PDFs that `pdfunite` cannot merge. The locator now falls back to a narrowly page-selected Ghostscript excerpt.
3. Calgary and Edmonton exposed unlabeled printed section totals and separately presented capital contributions/transfers. The prompt now supports the former, and the latter has a source-evidenced identity exception.
4. Hamilton exposed other comprehensive income in the accumulated-surplus roll-forward. That exception is accepted only when matching wording exists on a cited page.
5. Two concurrent model calls timed out. Calls now have a 180-second bound and remain safely retryable because source SHA and extractor version form the idempotency key.

## Acceptance basis and limitations

“Passed” means every required concept is present; labels and numbers occur on the cited physical page; raw values reparse exactly; the selected column is the fiscal-year actual column; confidence is at least 0.8; and applicable PSAS identities balance within the printed scale. Identity exceptions are hard-gated by statement-page wording.

This is a high-confidence pilot, not a statistical accuracy estimate. The ten reports are text-bearing municipal PSAS statements; it does not establish performance on image-only scans, First Nations reporting formats, non-PSAS statements, handwritten material, or detailed note tables. Every extraction remains reviewable and can be approved or rejected as one unit.

The reproducible pilot artifacts are stored on the external drive under:

`/Volumes/floppy/york_factory/public_institutions/financial-extractions/pilot-top10/2026-08-27`

They include per-city JSON, the source configuration, the current-validator audit, `pilot_results.parquet`, and `pilot_facts.parquet`.
