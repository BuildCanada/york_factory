# National public-institutions release validation

Release: `2026-08-21`
Schema: `1.0`
Geography vintage: Statistics Canada SGC 2021
Bundle: `/Volumes/floppy/york_factory/public_institutions/releases/public-institutions-2026-08-21`

## Final row counts

| Table | Rows |
| --- | ---: |
| releases | 1 |
| sources | 11,342 |
| institutions | 4,425 |
| identifiers | 2,597 |
| relationships | 1,436 |
| geographies | 3,487 |
| institution_geographies | 3,550 |
| coverage | 103 |
| documents | 13,870 |
| document_assets | 11,825 |

Government-level counts are 620 First Nation, 5 Inuit, 8 Métis, 3,478 municipal, 122 regional, 14 provincial/territorial, and 178 other institutions.

## Validation performed

- Imported all 13 jurisdiction manifests and the normalized First Nations manifest in one PostgreSQL transaction.
- Verified every emitted archived asset against safe path containment, byte size, SHA-256, declared MIME, and PDF/OOXML content markers.
- Exported ten Zstandard-compressed Parquet tables with DuckDB 1.5.0.
- Verified every file in `checksums.sha256`.
- Applied `postgres_schema.sql` to an empty PostgreSQL 17 database and ran the generated DuckDB loader.
- Compared all ten consumer-table row counts with the source database; every count matched.
- Confirmed that `ca/bc/shishalh-nation-government-district` and `ca/fn/shishalh-nation` both exist as distinct institutions.
- Confirmed that all 160 B.C. `member_of` relationships survived export and reload.
- Ran 42 targeted tests with 177 assertions and no test failures or errors.
- Inspected 33 ontology files with RuboCop; no offenses. `zeitwerk:check` and `git diff --check` pass.

The test command emits a pre-existing multi-database test-harness warning because the primary and queue configurations resolve to the same temporary validation database. The requested test files nevertheless run to completion with zero failures.

## Fable review resolution

- Corrected Alberta's Kananaskis semantic ID and represented the eight Métis Settlement governments.
- Preserved Improvement District No. 349 as historical and represented Diamond Valley succession.
- Kept the proposed District of Okanagan Falls inactive until its legal effective date.
- Moved the shíshálh Nation Government District into `ca/bc` and kept the ISC band in `ca/fn`.
- Added B.C. regional districts, Islands Trust, and 160 sourced membership edges.
- Separated audited statements, annual reports, B.C. SOFI disclosures, and financial data returns.
- Removed Statistics Canada geography codes from organization identifiers.
- Added explicit release coverage rows so absence is not confused with a completed search.
- Corrected Quebec geography/entity conflation, Northwest Territories duplicate band-government representations, and Saskatchewan NSAD classification.

## First Nations archive

The normalized layer contains 620 standalone band governments, 461 official websites, 620 headquarters geography links, and 6,351 FNFTA statement records spanning fiscal years 2013-14 through 2025-26. It excludes 18 parented ISC subgroups from the standalone count while preserving them in the source audit.

The archive recovered 4,007 statement binaries (4,005 PDF and 2 DOCX), totalling 8,743,981,816 bytes. All recovered files pass hash, size, and format checks. The remaining 2,344 URLs are retained as explicit failures: 2,333 upstream HTTP 500 responses and 11 SSL resets. These are suitable for a future dated retry and are not presented as missing statements.

## Honest shallow-release limits

- Jurisdiction rosters are complete only where `coverage.parquet` says `complete`; several provinces and territories have partial roster, website, or geography coverage.
- Province-wide audited-statement crawling is complete only for sources that exposed usable archives. Other jurisdictions are explicitly `partial`, `not-searched`, or `unavailable` by subject.
- Quebec aggregate returns and the Ontario FIR index are not relabelled as audited financial statements.
- Inuit, Métis, treaty, and self-government forms are preserved where the jurisdiction adapters expose them, but this release is not a complete national inventory of every Indigenous governing body outside the ISC band roster.
- Crown corporations, departments, police, fire, health, education, and other organization classes are supported by the schema but are not comprehensively populated by this local-government-and-band release.
- Binary archive paths are exported only when an upstream licence supports redistribution. The source archive remains on the floppy drive for internal reproducibility.
