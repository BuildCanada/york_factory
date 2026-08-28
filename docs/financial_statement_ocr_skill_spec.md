# Financial Statement OCR Agent Skill Specification

## Decision

Create a repo-local skill named `ocr-financial-statements` at
`.agents/skills/ocr-financial-statements/`. One invocation processes one source PDF and
produces a page-complete, provenance-preserving OCR package plus structured financial
extractions. It may self-verify and retry its own output, but it must not mark that output as
independently reviewed.

For the trusted-data gate, add a companion `review-financial-statement-ocr` skill or require a
fresh agent invocation with no extractor context. This follows the same claim/review separation
used by York Factory's KPI skills: self-verification catches mechanical errors, while an
independent pass prevents the extractor from approving its own assumptions.

The core invariant is:

> Every physical page in the exact archived source bytes has one source-qualified page-ledger
> entry, and every non-blank page has a complete OCR representation or an explicit blocking
> review flag.

Structured balance-sheet and operations JSON is not evidence that the entire financial
statement was extracted. The complete OCR package is the evidence layer; normalized financial
tables are derived claims with links back to page regions and raw tokens.

## Why the Current Pipeline Needs This Gate

The existing `/Volumes/floppy/FinancialStatements` code has useful building blocks:

- whole-PDF classification recognizes the major statements, notes, schedules, auditor reports,
  management responsibility pages, signatures, covers, contents, rotations, and blank pages;
- Pydantic models constrain financial position, operations, notes, and remuneration output;
- mechanical verifiers check accounting equations, row and column totals, accumulated-surplus
  flow, net debt, missing fields, structural patterns, digit errors, and transpositions;
- legacy verifiers also implement cross-statement and year-over-year comparisons;
- the web app already displays source pages beside extracted data and validation results.

However, the current pipeline cannot prove whole-document extraction:

- Local audit: 5,354 of 5,812 financial-statement metadata records do not map every physical
  financial-statement page.
- Local audit: 4,772 records have the single `notes` mapping pointing at the remuneration source,
  demonstrating that mappings from two source PDFs can overwrite one another.
- `page_mapping` is keyed by document type rather than `(source document, page number)`, so
  financial-statement notes and remuneration notes can collide.
- The classifier response is accepted without proving `total_pages` equals the PDF page count or
  that page numbers are unique, contiguous, in range, and exhaustive.
- Chunking can mark a report complete when only some chunks were created and other chunks failed.
- Out-of-range chunk ranges are clamped instead of rejected.
- A schema-invalid LLM response can be saved as raw data after Pydantic validation fails.
- Extractions link to a chunk or R2 path, but individual facts generally lack page, table, cell,
  bounding-box, and raw-token provenance.
- Notes verification checks only that notes exist and have titles/content; it does not prove note
  continuity, page coverage, table completeness, or agreement with the source.
- The database-oriented verifier omitted the legacy cross-statement and year-over-year checks.
- A validation result is converted to a synthetic confidence of `1.0` or `0.5`, which is not an
  observed OCR/extraction confidence.
- Whole-PDF model calls use non-deterministic settings and self-reported confidence; average
  confidence can hide one catastrophically weak page.

A representative 102-page scanned statement makes the risk visible. Its real note pages occupy
odd-numbered pages interleaved with blank scan backs. The metadata recognizes the blank backs but
loses most financial-statement notes after the remuneration mapping is merged. It also classifies
rotated pages explicitly titled `Schedule 2` and `Schedule 3` as primary accumulated-surplus and
operations statements. A totals-only verifier can still pass the surviving primary statements.

## Scope

The skill must process the entire source artifact, including:

- cover and title pages;
- table of contents;
- management-responsibility statement;
- independent auditor's report, opinion, signature, and date;
- every primary financial statement present;
- all notes, including prose, tables, continuations, and accounting policies;
- all schedules, appendices, segmented disclosures, and supplementary tables;
- signature pages and deliberately blank pages;
- English, French, and bilingual documents;
- native-text, scanned, mixed, rotated, skewed, duplex, and partially unreadable PDFs.

The skill does not decide whether a financial result is good or bad, reinterpret the auditor's
opinion, infer obscured values, or silently repair the source. It transcribes, structures,
reconciles, and flags.

## Required Artifacts

Store immutable, versioned artifacts keyed by the source SHA-256 and extraction run ID.

### 1. Source record

Record:

- source URL and R2 path;
- byte length, MIME and PDF magic;
- SHA-256;
- PDF page count, version, encryption state, and parse warnings;
- expected institution/BCID and fiscal period from the downloader;
- detected institution, period, language, and document type from the document body;
- renderer, OCR engine, vision model, prompts, settings, and code versions.

Never verify against a second fetch without comparing its hash to the archived bytes.

### 2. Page ledger

Use a composite identity, never a document-type key:

```json
{
  "source_sha256": "...",
  "page_number": 21,
  "render_sha256": "...",
  "width_points": 612,
  "height_points": 792,
  "detected_rotation": 0,
  "classification": "notes",
  "classification_confidence": 0.98,
  "blank_status": "non_blank",
  "native_text_chars": 0,
  "ocr_status": "complete",
  "ocr_confidence": 0.94,
  "section_ids": ["note:1"],
  "review_flags": []
}
```

There must be exactly one ledger row for every integer from `1..pdf_page_count`. Pages may contain
multiple `section_ids`, but have one physical identity and one primary classification.

### 3. Page OCR

Store a canonical JSON representation for each page:

- verbatim page text in reading order;
- blocks, lines, words, and confidence where the engine provides it;
- bounding polygon or bounding box for each block and word;
- tables with row/column indices, spans, header roles, raw cell text, and bounding boxes;
- headers, footers, printed page number, footnotes, signatures, and non-text visual regions;
- raw numeric tokens exactly as printed before normalization;
- detected language and reading direction;
- transformations applied to the render, such as rotation, deskew, crop, and tiling.

Also produce a page-delimited Markdown or plain-text derivative for search and debugging. Do not
use Markdown as the canonical representation because it cannot reliably preserve merged cells,
coordinates, or reading order.

### 4. Document structure

Create a structure manifest containing ordered sections and source page spans. Support at least:

- `cover_page`, `table_of_contents`, `management_responsibility`, `auditors_report`;
- `statement_of_financial_position`, `statement_of_operations`;
- `statement_of_changes_in_net_debt`;
- `statement_of_changes_in_net_financial_assets`;
- `statement_of_cash_flows`;
- `statement_of_remeasurement_gains_and_losses`;
- `statement_of_changes_in_accumulated_surplus` or fund balances;
- `notes`, with alphanumeric note IDs and continuation pages;
- `schedule`, with numeric, alphabetic, and named IDs;
- `signature_page`, `blank_page`, and `other`.

`other` is preferable to dropping or guessing a page.

### 5. Structured financial extraction

Keep the current normalized models where useful, but attach evidence to every value and label:

```json
{
  "raw_text": "(1,234)",
  "value_numeric": -1234,
  "currency": "CAD",
  "scale": 1,
  "source_sha256": "...",
  "page_number": 13,
  "table_id": "p13:t1",
  "row_index": 8,
  "column_index": 2,
  "bbox": [431.2, 288.0, 493.9, 301.8],
  "ocr_passes": ["native", "vision_b"],
  "agreement": 1.0
}
```

Preserve null, dash, zero, and blank as distinct raw states. Preserve the source header and unit
multiplier (`$`, `$000`, millions) separately from the normalized value.

### 6. Verification report

The report must contain:

- processing status and verification status as separate fields;
- every check with `id`, status, severity, evidence, affected pages/cells, and retryability;
- page-level and field-level confidence based on observed agreement, not final status;
- all retries and whether they changed the transcription;
- unresolved flags and the exact review action required;
- artifact hashes so the report cannot be attached to a different extraction version.

## Skill Workflow

### Step 1: Resolve and freeze one source document

Accept one `annual_report_id`, or an exact `(bcid, fiscal_year_end, source R2 path)` tuple. Download
once, compute SHA-256, validate the body against the expected institution and fiscal period, and
use those exact bytes throughout the run.

Exit without writing derived artifacts when the response is HTML, truncated, encrypted without
a usable password, malformed beyond safe repair, or for the wrong institution/period. Record a
source-level failure rather than pretending the document has zero extractable pages.

### Step 2: Inventory and render every page

Use a deterministic PDF parser for the physical page count. Render every page at a baseline
resolution suitable for small financial-table type. Preserve full page boundaries. Detect page
rotation, skew, clipping, extremely low contrast, and duplex blank backs. Re-render hard pages at
higher resolution or in overlapping tiles.

Extract native PDF text when present, but do not assume a non-empty text layer is correct. Scanned
pages can contain a sparse or misregistered hidden OCR layer.

### Step 3: Classify with source-qualified pages

Classify all pages and keep every classification result. Validate the result mechanically before
building chunks:

- model `total_pages == parser page_count`;
- page numbers are integers, unique, in range, and exactly `1..page_count`;
- classification is valid for this source;
- no page is lost when multiple source documents are processed;
- an explicit `Schedule`, appendix, or note title takes precedence over a table's resemblance to a
  primary statement;
- minimum confidence is retained alongside average confidence;
- low confidence, `other`, or inconsistent section boundaries enter review.

Use the table of contents as a second, independent section inventory where present. Do not treat
it as ground truth without resolving printed-page versus physical-page offsets.

### Step 4: OCR every non-blank page

Choose a route per page:

- good native text: extract native text and layout, then compare selected regions with the render;
- scan or poor native layer: run layout-aware OCR on the rendered page;
- mixed page: combine native text with OCR for image-only regions;
- difficult page: retry with rotation, deskew, contrast adjustment, higher DPI, and tiles.

Treat tables as layout, not a stream of words. Extract header hierarchy and the full cell grid.
Never normalize numbers during raw OCR.

### Step 5: Run an independent OCR inventory

For self-verification, run a second pass that does not receive the first pass's transcription as
its answer. It may use a different engine/model or an independently prompted visual extraction.
Compare:

- normalized token sequences;
- all numeric and date tokens;
- table row/column counts and header assignments;
- section and note/schedule boundaries;
- page-level blank/non-blank decisions.

Agreement is evidence; model confidence alone is not. Any numeric disagreement, missing table
row, or conflicting blank decision triggers a targeted high-resolution retry and retains both
original observations in the audit trail.

### Step 6: Derive structured statements from the OCR evidence

Extract every primary statement, note, and schedule present. Require each normalized field to
point to its raw page evidence. Do not save schema-invalid output. Unknown structures should be
preserved as generic tables/sections and flagged rather than dropped.

### Step 7: Run deterministic verification

Run the complete check suite below. Reuse and centralize the reliable arithmetic logic from the
existing verifiers. Restore cross-statement and year-over-year checks in the database workflow.

### Step 8: Retry only what failed

Retry page regions or tables, not the whole document by default. On retry, compare versions and
accept a replacement only when it improves explicit checks or resolves independent disagreement.
Do not select the answer merely because it makes an accounting equation balance.

### Step 9: Publish a review package

Publish source page images, OCR overlays, raw/normalized cell values, deterministic checks, and
version diffs to the existing verification UI. Default navigation should start at the highest
severity unresolved page, not at the first primary statement.

### Step 10: Close with an honest status

Use these document-level outcomes:

- `PASS`: page-complete; all required OCR artifacts exist; no unresolved error; all applicable
  hard reconciliations pass.
- `PASS_WITH_WARNINGS`: page-complete and numerically sound, with non-blocking issues documented.
- `NEEDS_REVIEW`: usable output exists, but at least one ambiguity or failed verification needs an
  independent decision.
- `INCOMPLETE`: one or more non-blank pages, sections, tables, or required provenance links are
  absent.
- `FAILED`: source could not be safely processed or output is unusable.

`EXPLAINABLE`, `DIGIT_ERROR`, or `STRUCTURAL` may remain error categories, but they must not be
treated as approval states.

## Verification Checks

### A. Source and artifact integrity

| Check | Failure condition | Severity |
|---|---|---|
| Source hash binding | Extraction or report references different bytes | Error |
| File identity | MIME, magic, expected institution, document kind, or fiscal period conflicts | Error |
| PDF readability | Parser cannot enumerate all pages safely | Error |
| Artifact hash binding | OCR, structured JSON, and verification versions do not share a run/source hash | Error |
| Duplicate source reuse | Same source bytes appear under conflicting BCID/year metadata | Error/review |
| Stale extraction | Source hash changed after extraction | Error |

### B. Page completeness and rendering

| Check | Failure condition | Severity |
|---|---|---|
| Page-ledger equality | Ledger page set is not exactly `1..pdf_page_count` | Error |
| Source-qualified identity | A page mapping can be overwritten by another source PDF | Error |
| Range validity | Duplicate, overlapping, reversed, zero, or out-of-range pages | Error |
| Render completeness | Page render missing, zero-sized, clipped, or corrupt | Error |
| Blank-page corroboration | Blank classification lacks agreement from raster/text signals | Error/review |
| Rotation/skew | Text remains unreadable after recorded correction attempts | Error/review |
| Density anomaly | Non-blank page OCR density is an outlier from visually similar pages | Warning/review |
| Duplicate-page OCR | Adjacent/non-adjacent pages have implausibly identical content | Warning/review |

### C. Document-structure completeness

| Check | Failure condition | Severity |
|---|---|---|
| TOC reconciliation | Listed section/note/schedule cannot be located, after page-offset resolution | Error/review |
| Primary statement inventory | A listed or strongly implied primary statement is absent | Error |
| Auditor-report continuity | Opinion pages or auditor signature/date appear truncated | Error/review |
| Note continuity | Missing note IDs, lost continuations, conflicting IDs, or impossible order | Error/review |
| Schedule continuity | TOC-listed or cross-referenced schedule is missing | Error/review |
| Explicit-title precedence | A page titled as a schedule/note is relabelled as a primary statement | Error |
| Printed-page continuity | Unexpected gaps/duplicates not explained by covers or blank backs | Warning/review |
| Cross-reference closure | Statement note reference has no matching extracted note | Error |
| Orphan content | Non-blank page has no section or `other` assignment | Error |

Alphanumeric and compound note IDs (`1(a)`, `12A`) must be supported. Gaps are not automatically
errors when the document itself skips a number; they become review items unless the TOC or
cross-references prove omission.

### D. OCR and table fidelity

| Check | Failure condition | Severity |
|---|---|---|
| Independent token agreement | Passes disagree beyond the configured text threshold | Warning/review |
| Numeric-token recall | A visible numeric/date token is absent from the canonical page OCR | Error |
| Numeric-token agreement | OCR passes disagree on any material number, sign, decimal, or year | Error |
| Table-shape agreement | Row/column count, merged header, or continuation differs between passes | Error/review |
| Raw-token preservation | Normalized value has no verbatim raw token | Error |
| Column drift | Values appear shifted relative to headers or comparative years | Error |
| Sign semantics | Parentheses, minus signs, em dashes, blanks, and zeros are conflated | Error |
| Scale/currency | Page/table multiplier or currency is missing or applied inconsistently | Error |
| OCR confusion patterns | `O/0`, `I/l/1`, `S/5`, `B/8`, dropped comma/decimal, or split digits detected | Error/review |
| Text corruption | Replacement characters, mojibake, or abnormal non-language glyph rate | Warning/review |
| Page-boundary continuation | Heading/table continuation is duplicated or dropped across pages | Error/review |

A useful new completeness metric is numeric-token coverage:

```text
material numeric tokens assigned to a cell/field or explicit non-data role
--------------------------------------------------------------------------
material numeric tokens independently observed on the rendered source page
```

Require 100% disposition for financial tables. A token may be marked header, page number,
footnote marker, or ignored-with-reason, but it may not disappear silently.

### E. Existing accounting checks to retain

- total revenue minus expenditures, with document-specific other items, equals surplus/deficit;
- line items equal stated subtotals and totals;
- opening accumulated surplus plus annual result and explicit adjustments equals closing surplus;
- assets equal liabilities plus accumulated surplus/net assets;
- financial assets minus liabilities equals net financial assets/debt;
- net financial assets/debt plus non-financial assets equals accumulated surplus where applicable;
- remuneration row totals and column totals reconcile;
- remuneration month values and table structure are valid;
- missing mandatory totals, suspicious negatives, duplicates, post-total items, and subtotal
  inclusion patterns are flagged;
- discrepancies are categorized for likely digit, double-digit, transposition, omission, doubling,
  rounding, or structural errors.

Do not allow the verifier to try many arbitrary summation combinations and accept whichever is
closest without recording the exact formula supported by the source headers. That can hide a
column-assignment error.

### F. New cross-statement and disclosure checks

- Closing cash in cash flows equals cash/cash equivalents on financial position, allowing only a
  documented restricted-cash or overdraft presentation difference.
- Opening cash plus net change equals closing cash; operating, capital/investing, and financing
  subtotals equal their line-item sums.
- Closing net financial assets/debt in its changes statement equals financial position.
- Annual surplus/deficit in changes statements equals operations.
- Closing accumulated-surplus/fund-balance schedule equals financial position; component funds sum
  to the consolidated total.
- Tangible-capital-asset note/schedule reconciles opening cost, additions, disposals, write-downs,
  closing cost, accumulated amortization, and net book value; closing net book value agrees with
  financial position.
- Debt-note total and current portion reconcile to the related liability presentation when the
  document makes that relationship explicit.
- Segmented and program schedules sum to consolidated revenue and expense totals, with eliminations
  handled explicitly rather than forced to zero.
- Comparative figures for the same fiscal year agree across statements, notes, and the next year's
  comparative column, subject to explicit restatement labels.
- Budget columns are never compared to actual columns merely because they share a year.
- Restated, reclassified, and prior-period-adjustment labels are preserved and explain otherwise
  valid year-over-year differences.
- Entity name, consolidation scope, fiscal-period end, currency, scale, and language are consistent
  across cover, auditor report, statements, notes, and downloader metadata.
- Every primary-statement note reference resolves, and referenced note totals agree where the note
  states the same measure and basis.

These checks should emit `SKIP` with a reason when the necessary statement or disclosure is not
present. A skipped check is never evidence of completeness.

## Independent Review Contract

The independent reviewer must receive only:

- the source bytes/hash and rendered pages;
- the candidate OCR/extraction and verification report;
- the review scope and unresolved flags.

It must not receive the extractor's private reasoning or intended answer. Review in risk order:

1. source identity and page-ledger equality;
2. every page/table with OCR disagreement or low confidence;
3. all failed accounting/cross-statement checks;
4. every notes/schedule boundary and TOC mismatch;
5. a deterministic sample of passing pages, including at least one prose page and each financial
   table type;
6. final whole-document page-flip review before approval.

Approval should be append-only and identify reviewer, run, source hash, extraction version,
decision timestamp, corrections, and evidence. Corrections to raw OCR must produce a new version
and rerun all dependent structured and accounting checks.

## Proposed Skill Body

The eventual `SKILL.md` should stay concise and route details to references/scripts:

```yaml
---
name: ocr-financial-statements
description: Produce page-complete, provenance-preserving OCR and structured financial data from public financial-statement PDFs, then self-verify page coverage, table fidelity, accounting equations, cross-statement consistency, and year-over-year comparatives. Use for one archived Canadian public-sector or First Nations financial statement when Codex needs to OCR, re-OCR, extract, reconcile, or prepare it for independent review.
---
```

Recommended folder:

```text
.agents/skills/ocr-financial-statements/
├── SKILL.md
├── agents/openai.yaml
├── references/
│   ├── artifact-schema.md
│   ├── verification-checks.md
│   └── financial-statement-archetypes.md
└── scripts/
    ├── audit_page_ledger.rb
    ├── compare_ocr_passes.rb
    ├── verify_artifact_hashes.rb
    └── build_review_package.rb
```

The scripts should be deterministic and engine-neutral. OCR provider calls and database writes
belong in the FinancialStatements CLI/API, not improvised shell snippets in the skill.

## Required Pipeline Changes Before the Skill Can Be Operational

1. Replace type-keyed page mappings with source-qualified page ledger records.
2. Add a stable OCR artifact schema and R2 paths keyed by source hash/run/version.
3. Add per-block/table/cell provenance to structured extractions.
4. Make classifier completeness validation a hard precondition to chunking.
5. Fail chunking atomically or record explicit partial state; never mark complete after partial
   chunk errors.
6. Reject out-of-range or overlapping page ranges instead of clamping them.
7. Make Pydantic/schema validation failure fatal for publication.
8. Add deterministic low-temperature/structured responses where the provider supports them and
   retain the raw model response.
9. Centralize the legacy and database verifier logic, including cross-statement and year-over-year
   checks.
10. Add OCR/page-ledger and review-decision tables or equivalent append-only API resources.
11. Extend the web verifier to all page types and show source-qualified pages, OCR overlays,
    disagreements, evidence cells, and unresolved document-level checks.
12. Keep reported confidence as a measured field; do not derive it from PASS/FAIL.

## Acceptance Tests

Before enabling batch processing, the skill and pipeline must pass a fixture set containing:

- a native-text financial statement;
- a fully scanned statement;
- a mixed native/scanned statement;
- a rotated or skewed table;
- duplex scanning with alternating blank backs;
- a bilingual/French statement;
- multi-page tables with repeated headers;
- notes containing dense tables and prose continuations;
- alphanumeric note and schedule IDs;
- a restated comparative year;
- `$000` or millions scaling;
- parentheses, dashes, zeros, and blanks in the same table;
- a deliberate digit error, transposition, missing row, shifted column, missing page, duplicate
  page, wrong fiscal year, and source-hash change.

The most important assertions are:

- page-ledger equality always fails on a missing, duplicate, or foreign-source page;
- blank backs pass without being mistaken for OCR failures;
- every material financial-table number has source coordinates and raw text;
- independent numeric disagreement blocks PASS;
- structured extraction cannot publish after schema validation failure;
- each accounting check fails on its targeted mutation and passes on the clean fixture;
- corrections invalidate and regenerate all dependent verification results;
- the review UI can navigate directly from a failed check to the exact rendered cell.

## Rollout

1. Run page-ledger audit only against the existing corpus and quantify failure families.
2. Produce OCR packages without changing current canonical extractions.
3. Compare new OCR-derived values to current JSON and route disagreements to the verifier UI.
4. Require page completeness and provenance for new downloads.
5. Backfill highest-risk documents first: incomplete mappings, wrong-source notes, scanned pages,
   low-confidence classifications, failed arithmetic, and restated years.
6. Make independent approval the publication gate only after fixture and shadow-run error rates are
   acceptable.
