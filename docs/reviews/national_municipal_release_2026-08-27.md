# National municipal financial-statement release — 2026-08-27

## Release artifacts

- Versioned configuration: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-27/national-municipal-release-config-v6.json`
- Issuer-only audit: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-27/national-issuer-audit-v6.json`
- Predecessor-aware audit: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-27/national-lineage-audit-v6.json`
- Per-manifest revalidations: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-27/validations-v6/`
- Issuer gap IDs: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-27/issuer-gap-ids-v6/`
- Predecessor-aware gap IDs: `/Volumes/floppy/york_factory/public_institutions/sources/national-municipal-ten-year-coverage/2026-08-27/lineage-gap-ids-v6/`

SHA-256:

- config: `2eca4d66c4363875b93c1baeb8c729e5e4eb4cb1c9972b39b6941359ff729621`
- issuer audit: `64cc51e7d61ed2511ea9885c469f35eca60b42c99bfa72160b5c45a284e698ca`
- predecessor-aware audit: `669bf955eb4e4a59cca46dce5f0ba1b0c67cae1e647b4789680accd13ea7d351`

## Coverage result

The release scopes 3,777 institutions. Of these, 2,939 have at least one valid, locally archived financial-statement year and 838 have none. On an issuer-only basis, 1,318 of 2,939 have ten distinct years; 1,621 remain short by 8,593 year slots. Predecessor lineage makes Diamond Valley complete, leaving 1,620 short by 8,585 slots. Caraquet is separately reported as lineage-only and does not alter the eligible denominator.

This is not full ten-year coverage. Percentages must always identify whether the denominator is the full scoped roster (3,777) or institutions with at least one valid statement (2,939).

## Validation result

All 13 manifests have zero validation errors and the coverage audits have zero asset-integrity errors. Revalidation uses the production validator; it is not described as an independent implementation.

The validator emits 17 non-blocking duplicate-content warnings: 3 in Alberta and 14 in New Brunswick. They represent predecessor/successor duplication or an explicitly shared regional report. The PAAC and Le Goulet/Shippagan misattributions identified during review were corrected before v6. Remaining warnings stay explicit for human review.

## Deliberate limitations

- Ten-year completion means any ten distinct fiscal years; it does not require a contiguous or recent ten-year window.
- Fiscal-year values follow issuer/report conventions and may not align to a single calendar-year convention.
- Financial statements received strict content validation. Annual reports are included in asset and document totals but were not given the same content-level audit.
- Strict-audit rejection files are tombstone/rejection registers; rejected assets are absent from the published manifests.
- `succeeds` covers sourced legal or administrative succession and should not be interpreted as only one subtype such as annexation or amalgamation.
