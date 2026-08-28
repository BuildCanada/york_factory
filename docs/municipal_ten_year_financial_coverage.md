# Municipal ten-year financial-statement coverage

## Goal

For every scoped, active Canadian municipal institution that has at least one locally archived financial statement, preserve a ten-fiscal-year financial history whenever the legal institution or its sourced predecessor lineage existed for that period.

The product reports two measures so that a merger never rewrites history:

- **Issuer-only coverage** counts only statements issued by the institution named on the PDF.
- **Lineage coverage** counts the union of issuer years and years issued by institutions connected through one or more sourced `succeeds` relationships.

A predecessor document always remains attached to the predecessor's canonical ID. Lineage coverage is a query-time union, not document reassignment. Continuations and renames retain a canonical ID; amalgamations, dissolutions, splits, and genuinely new corporations use separate IDs and dated relationships.

## Valid statement

A fiscal year counts only when at least one linked asset passes every check:

1. the archived file exists under the content-addressed asset root;
2. byte size and SHA-256 match the manifest;
3. the payload starts with a PDF header;
4. PDF text identifies the legal institution by its name or an exact, contextual
   upstream identifier (currently the `qc.code-geographique` printed beside
   `Code géographique` on the standardized Québec cover);
5. the document contains an independent auditor's report and municipal financial statements; and
6. the fiscal year extracted from the PDF contents matches the document work's fiscal period and canonical ID.

Fiscal-year extraction uses the earliest explicit period evidence in document
order. This keeps a later restated-comparative note (for example, a 2018
comparison inside a 2019 statement) from changing the primary fiscal year.

Upload dates, page publication years, filenames, annual financial returns, budgets, unaudited summaries, and statements belonging to utilities or other subsidiaries do not satisfy the gate.

## Reproducible audit

`script/audit_municipal_ten_year_financial_coverage.rb` reads the pinned national coverage configuration and writes an immutable JSON audit. By default it reports issuer-only coverage. `--include-predecessors` additionally follows transitive, sourced `succeeds` edges. `--ids-dir` emits one deterministic shortfall worklist per province.

`script/audit_municipal_financial_statement_assets.rb` performs the stricter PDF-content validation before a manifest is eligible for the national gate.
It extracts every page and uses a bounded OCR fallback when a hybrid PDF has an
embedded-text cover or annual-report shell but scanned issuer, auditor, or
fiscal-period pages. A national gate configuration must set
`included_statuses` to `["active"]`; rows without an explicit status retain the
legacy meaning of active, while dissolved predecessors remain queryable only
through lineage.

The Québec identifier rule preserves stable-code histories across legal-name
changes, while requiring the labelled cover field prevents a coincidental
five-digit amount from satisfying issuer validation.

The initial 2026-08-25 issuer-only baseline contains 2,898 eligible institutions: 418 have ten years and 2,480 have a combined 18,661 missing year slots. Existing Alberta lineage data raises the lineage-complete count to 419; additional reform histories are being modeled rather than inferred.

## Promotion order

Each province is promoted independently:

1. freeze official source indexes and municipal/archive discovery results;
2. archive PDFs by SHA-256 on the external drive;
3. sanitize candidate batches;
4. merge documents without overwriting the prior manifest;
5. correct or reject content-proven fiscal-year conflicts;
6. run the strict asset audit and schema validation;
7. pin the new provincial manifest in a new national configuration; and
8. rerun both issuer-only and lineage coverage gates.

No in-progress scrape or unvalidated batch is counted.
