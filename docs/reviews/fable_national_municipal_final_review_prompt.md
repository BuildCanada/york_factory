# Fable review: national municipal ten-year financial-statement release

Act as an independent, skeptical data-product reviewer. This is a read-only review; do not modify files or run mutation commands.

Review the completed Canadian municipal financial-statement ontology/release pipeline and identify any deficiencies that could make the reported coverage, issuer attribution, fiscal-year attribution, predecessor handling, or asset integrity misleading.

Primary artifacts:

- Ontario final manifest: `/Volumes/floppy/york_factory/public_institutions/sources/on-local-governments/2026-08-25/release-manifest-ten-year-official-sites-final-strict-v6.json`
- Ontario final strict audit: `/Volumes/floppy/york_factory/public_institutions/sources/on-local-governments/2026-08-25/financial-statement-final-strict-audit-v6.json`
- Ontario validator: `/Volumes/floppy/york_factory/public_institutions/sources/on-local-governments/2026-08-25/release-manifest-ten-year-official-sites-final-validation-v6.json`
- National config: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-25/national-final-config-v1.json`
- National issuer audit: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-25/national-final-issuer-audit-v1.json`
- National lineage audit: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-25/national-final-lineage-audit-v1.json`
- Ontario independent validator: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-25/on-final-independent-validation-v1.json`
- Issuer gap IDs: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-25/national-final-issuer-gap-ids-v1/`
- Lineage gap IDs: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-25/national-final-lineage-gap-ids-v1/`

Implementation to inspect:

- `script/audit_municipal_financial_statement_assets.rb`
- `script/audit_municipal_ten_year_financial_coverage.rb`
- `script/reassign_manifest_financial_statement_years.rb`
- `script/sanitize_municipal_report_batch.rb`
- `script/validate_public_institution_manifest.rb`
- `script/scrape_municipal_financial_reports.rb`
- relevant tests under `test/scripts/`

Known final results to independently verify rather than assume:

- Ontario validator reports zero errors, 444 institutions, 2,145 documents, 2,406 assets.
- Ontario strict audit reports 2,049 validated financial-statement assets, seven rejected assets, and zero remaining fiscal-year mismatches.
- National issuer-only totals: 2,939 eligible, 1,318 complete, 1,621 short, 8,593 missing year-slots, zero asset-integrity errors.
- National sourced-lineage totals: 2,940 eligible, 1,319 complete, one lineage-assisted completion, 1,621 short, 8,594 missing slots, zero integrity errors.

Pay special attention to:

1. Whether `eligible` can hide active municipalities with no downloaded statement and how that limitation is communicated.
2. Status/type scoping consistency across provinces and territories.
3. Whether issuer-only and lineage denominators are comparable.
4. Whether sourced `succeeds` direction and transitive traversal are correct.
5. Duplicate years/assets, canonical-ID versus fiscal-period agreement, and wrong-issuer risks.
6. The seven Ontario rejects and whether their removal can leave misleading empty documents or coverage.
7. Whether the UTF-8 OCR normalization fix is sufficient and tested.
8. Reproducibility/versioning/provenance weaknesses in the static release.
9. Any discrepancy between source manifest release dates and the final audit/retrieval dates.
10. Anything that should block release versus anything that should merely be documented as a limitation or follow-up.

Return:

- `VERDICT: PASS`, `PASS WITH DEFICIENCIES`, or `BLOCK`.
- A numbered finding list with severity (`BLOCKER`, `HIGH`, `MEDIUM`, `LOW`), exact evidence, and concrete remediation.
- A short section of computations independently checked.
- A final minimal action list ordered by release priority.
