# Municipal Financial Statement Fact Extraction

## Decision

Extract a small, reviewable set of headline PSAS financial facts from an archived municipal
financial statement. This is a fact-extraction pipeline, not a page-complete archival OCR
system.

The first production scope is the document's current fiscal-year actual column for:

- total financial assets;
- total liabilities;
- net financial assets or net debt;
- total non-financial assets;
- accumulated surplus;
- opening accumulated surplus, when printed;
- total revenue;
- total expenses; and
- annual surplus or deficit.

Never synthesize a fact the source does not print. In particular, Canadian public-sector
statements commonly present financial assets and non-financial assets rather than a corporate
`total assets` line.

## Core invariants

1. Every extraction is bound to the exact archived PDF by SHA-256.
2. Every fact identifies a physical PDF page and preserves its verbatim label and numeric text.
3. The extracted column year must equal the ontology document's fiscal year.
4. Raw text must deterministically reparse to the stored normalized value, including scale and
   sign.
5. Schema-invalid model output creates no facts.
6. Failed accounting identities block auto-acceptance.
7. Re-extraction is versioned and append-only. Approved facts are never silently mutated.

## Why the earlier design was reduced

The earlier proposal required page ledgers, render hashes, word and cell bounding boxes, two OCR
passes, a complete document-structure manifest, note and schedule continuity, and dozens of
whole-document checks. Those are useful for an archival transcription product, but unnecessary
for nine human-verifiable totals.

The retained provenance tuple is:

```text
(document canonical ID, asset SHA-256, physical page, raw label, raw numeric text)
```

A reviewer can open the immutable archived PDF at the recorded page and verify the claim. Full
page OCR artifacts, bounding boxes, independent OCR consensus, note extraction, cash-flow
checks, year-over-year comparisons, and a dedicated review UI are deferred.

## Data model

The extraction tables live in `warehouse` but are not release-scoped. They refer to ontology
records using stable document/institution canonical IDs and the immutable asset SHA rather than
foreign keys into a dated release.

### `financial_statement_extractions`

- `institution_canonical_id`
- `document_canonical_id`
- `asset_sha256`
- `fiscal_year_end`
- `statement_basis`: initially `consolidated` or `non_consolidated`
- `language`: `en`, `fr`, or `bilingual`
- `extractor_version`
- `llm_model`
- `status`: `pending`, `extracting`, `extracted`, `needs_review`, `approved`, `rejected`, or
  `failed`
- `check_results`: deterministic check results
- prompt and response snapshots
- error details and timestamps

`(asset_sha256, extractor_version)` is unique.

### `financial_statement_facts`

- extraction ID
- canonical concept
- normalized CAD value
- verbatim raw label and raw numeric text
- source scale: `1`, `1_000`, or `1_000_000`
- statement: `financial_position`, `operations`, or `accumulated_surplus`
- physical source page
- printed column-year label
- informational extraction confidence

One extraction has at most one fact for each concept. Trust is assigned to the complete
extraction rather than to individual rows.

## Workflow

### 1. Resolve and freeze the source

Use a preferred archived PDF asset from a `financial-statements` document. Confirm PDF magic,
byte size, SHA-256, expected institution, and expected fiscal year using the exact archived
bytes. Never verify against an un-hashed second fetch.

### 2. Locate statement pages deterministically

Extract layout-preserving text per page. Search English and French headings for the statement of
financial position, operations, and accumulated surplus. Explicit `schedule`, `note`, or
`appendix` headings do not count as primary statements.

Only the matching pages and at most one neighbouring page are sent to a model. This is required
for large annual reports, not merely an optimization. If a page has no usable text, apply bounded
OCR to that page. Failure to locate the two primary statements is a review/failure condition.

### 3. Extract a strict response

The model receives only the located pages, the expected institution and fiscal year, the nine
allowed concepts, and a strict JSON contract. It returns the raw label, raw number, excerpt page,
scale evidence, column label, and confidence. The deterministic parser—not the model—derives the
signed whole-dollar value.

Do not extract a prior-year comparative or budget value. Do not infer a missing fact. French and
bilingual headings and number formats are first-class inputs.

### 4. Validate deterministically

Each check returns `pass`, `fail`, or `skip` with evidence. A skipped check is not a pass.

- `source_identity`: the extraction is bound to the expected document canonical ID and exact source hash.
- `raw_parse`: `raw_text × scale` exactly reproduces the normalized value.
- `column_year`: every fact is from the expected fiscal-year column.
- `position_net`: financial assets minus liabilities equals net financial assets/debt.
- `position_surplus`: net financial assets/debt plus non-financial assets equals accumulated
  surplus.
- `operations_surplus`: revenue minus expenses equals annual surplus/deficit, skipped with a reason
  when the statement separately presents capital contributions, transfers, gains, or losses
  between those totals.
- `surplus_rollforward`: opening accumulated surplus plus annual surplus equals closing
  accumulated surplus, skipped with a reason when remeasurement or restatement items apply.
- `revenue_per_capita`: flag likely scale errors using available population metadata.

Identity tolerance is the source scale to allow printed rounding. A failure may be annotated as a
likely transposition, digit, doubling, or scale error, but the annotation never turns a failure
into a pass.

PSAS sign conventions must be explicit. A printed positive `net debt` represents a negative net
financial-assets value. Parentheses are negative; dash, blank, and zero remain distinct.

### 5. Gate and review

An extraction becomes `extracted` only when:

- every fact reparses;
- every fact uses the expected column year;
- all applicable accounting identities pass; and
- minimum fact confidence is at least `0.8`.

Otherwise it becomes `needs_review`; malformed output becomes `failed`. During the initial pilot,
all results receive a manual source check regardless of status. Approval/rejection must be
explicit and append-only.

## Table handling

The pipeline does not attempt to reconstruct an entire table grid. It extracts only named total
rows and their association with the current-year column. Layout text and rendered statement pages
provide the row/column evidence.

Column association is a hard gate. If headers are merged, values drift between columns, or the
current-year actual column cannot be distinguished from budget/comparative columns, the result
requires review. Physical row/column indexes and bounding boxes can be added later without
invalidating the retained page-and-verbatim provenance.

## Bilingual parsing requirements

The deterministic parser must support:

- comma-grouped English numbers such as `1,234,567`;
- space and non-breaking-space grouping such as `1 234 567`;
- decimal comma where a source actually uses decimals;
- parentheses and explicit minus signs;
- French concepts including `actifs financiers`, `passifs`, `actifs financiers nets`,
  `dette nette`, `actifs non financiers`, `excédent accumulé`, `revenus`, `charges`, and
  `excédent de l'exercice`;
- English, French, or bilingual scale evidence such as dollars, thousands, `$000`, `en milliers`,
  millions, or `en millions`.

## Pilot and acceptance

Run one suitable audited statement for Toronto, Montréal, Calgary, Ottawa, Edmonton, Winnipeg,
Mississauga, Vancouver, Brampton, and Hamilton.

The pilot report records:

- selected document and source SHA;
- extracted facts and pages;
- every deterministic check;
- manual comparison result for each fact;
- false positives, missing facts, and source-selection failures; and
- changes made after each iteration.

The acceptance bar is 100% accuracy for every fact marked approved. Missing or ambiguous facts
may remain `needs_review`; they may not be silently accepted. Mutation tests must prove that a
wrong digit, sign, scale, year column, or shifted value fails an appropriate deterministic check.

## Deferred work

- page-complete OCR and page ledgers;
- per-word or per-cell coordinates;
- dual-engine agreement;
- full note, schedule, remuneration, cash-flow, TCA, and segment extraction;
- year-over-year comparisons;
- automatic batch approval;
- a specialized review UI; and
- multi-year backfill.
