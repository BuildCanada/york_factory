# Municipal financial statements deployment

This release is split into code and immutable public data. The York Factory and
CanadaSpends pull requests may be reviewed while extraction continues, but
production data must not be promoted until the national finalizer has frozen and
validated one release.

## Pull request shape

- York Factory is a stacked pull request based on `feat/public-institution-ontology`
  (PR #111). It owns the Warehouse schema, extraction/review pipeline, public API,
  census context, verification results, and release tooling.
- CanadaSpends is a stacked pull request based on
  `federal-public-accounts-pipeline` (PR #275). It owns the municipal directory,
  year pages, context, verification display, and Sankey rendering.
- Merge each parent before its stacked municipal pull request. Deploy York Factory
  before CanadaSpends.

## Release gates

Use release `2026-08-27` for the current national run. Before exporting it:

1. Let every jurisdiction handoff and reviewer finish, then run
   `script/run_national_financial_finalization.zsh`.
2. Require zero detailed rows in `pending`, `extracting`, or `extracted`; zero
   terminal extraction rows without saved checks; and zero approved rows without
   deterministic review provenance.
3. Preserve the final coverage, numeric, scale, lineage, issuer, and test-result
   artifacts alongside the release. Failures and unavailable documents remain
   explicit; they are not silently dropped.
4. Run the York Factory test suite and the CanadaSpends Vitest suite/build from
   the exact commits being deployed.
5. Export the immutable ontology release only after its `published_at` includes
   the final review timestamps. Never edit an already-published release in place;
   if the release has already been published, create a new dated release.

## Data promotion contract

Do not copy the local development database into production. The promotion unit is
one immutable, checksummed release directory produced by:

```sh
bin/rails institution_ontology:export[2026-08-27,tmp/public-institutions-2026-08-27]
```

The exported directory must contain the ontology, documents, document-asset
metadata, approved extractions, facts, detailed revenue/expense line items,
census context, manifest, SQL loader, and `SHA256SUMS`. Upload it under a
versioned R2 key such as
`municipal-financial-statements/releases/2026-08-27/`; never overwrite that key.
Archived source binaries remain content-addressed by SHA-256 in the archival R2
bucket.

The API reads the Rails `warehouse` schema, while the exporter's generic SQL
loader targets the read-only `public_institutions` interchange schema. Therefore
the release is not production-ready until York Factory has a verified,
idempotent importer that maps the release's natural identifiers back into the
existing Warehouse release. That importer must:

- verify `SHA256SUMS`, `manifest.json`, release version, schema version, and every
  referenced document/asset before opening a transaction;
- refuse a different payload for an already-imported release;
- upsert only census profiles and the selected release's approved extractions,
  facts, and line items by natural identity, without using local database IDs;
- save the import manifest SHA-256 and row counts for audit and retry safety;
- stage and validate all rows, then make them visible atomically;
- provide a dry-run that performs every validation without writing.

Until that importer is implemented and tested, the supported fallback is to run
the deterministic extraction/review pipeline against the imported immutable
source release in production. A whole-database dump/restore is not a supported
promotion path.

## York Factory deployment

After PR #111 and the stacked York Factory PR merge:

```sh
bin/kamal deploy
bin/kamal app exec --reuse 'bin/rails db:migrate:status'
```

The seven municipal migrations are additive except for replacing extraction and
line-item unique indexes and adding check constraints. Before deploy, verify the
production table has no rows that violate the new constraints. Keep the API
unreferenced by CanadaSpends until migrations and data promotion succeed.

Promote data only through the verified importer described above (first with
`DRY_RUN=1`), then verify at minimum:

```text
GET /api/v1/warehouse/municipal_financial_statements
GET /api/v1/warehouse/municipal_financial_statements/on/toronto/2025
GET /api/v1/warehouse/municipal_financial_statements/ns/halifax
```

Each published statement must expose a non-empty verification check list. Sample
records must also have source links, census context where mapped, and balanced
Sankey data where detailed line items passed validation.

## CanadaSpends deployment

Set the production server-side environment variable:

```text
YORK_FACTORY_API_URL=https://yorkfactory.buildcanada.com/api/v1
```

Merge and deploy the stacked CanadaSpends pull request only after the York API
smoke tests pass. Verify the municipal directory, Toronto's newest reviewed year,
one Atlantic municipality, bilingual routes, year switching, source links,
verification results, per-capita context, and the Sankey.

The Cloudflare quick tunnel is a disposable preview only. It is not a production
origin and its URL must not be committed or configured in production.

## Rollback

- Roll CanadaSpends back first; York's new API can remain unused.
- Roll York code back only while leaving additive tables/columns in place. Do not
  reverse schema migrations during an incident.
- If a data payload is wrong, disable the frontend route or mark the affected
  release unpublished, retain the import audit, and promote a corrected new
  release. Do not mutate the immutable R2 key or erase failed test evidence.
