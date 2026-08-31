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
4. Upload the finalizer, coverage, numeric, scale, lineage, issuer, and test logs
   to the immutable release's R2 `audit/` prefix. Files left only on
   `/Volumes/floppy` do not satisfy this gate.
5. Run the York Factory test suite and the CanadaSpends Vitest suite/build from
   the exact commits being deployed.
6. Freeze the financial-data bundle at an explicit review cutoff. The ontology
   release's `published_at` predates these extractions, so its current exporter
   would emit none of the newly reviewed rows. Never change or recut an existing
   bundle; corrections use a new dated bundle.

## Data promotion contract

Do not copy the local development database into production. The promotion unit is
one immutable, checksummed release directory produced by:

```sh
bin/rails institution_ontology:export[2026-08-27,tmp/public-institutions-2026-08-27]
```

The exported directory must contain the ontology, documents, document-asset
metadata, approved extractions, facts, detailed revenue/expense line items,
  census context, manifest, SQL loader, and `checksums.sha256`. Upload it under a
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

Until that importer and the immutable R2 uploader are implemented and tested,
production data promotion is blocked. Re-running the extraction pipeline in
production would re-derive rather than promote the reviewed result and is not a
supported fallback. A whole-database dump/restore is also not supported.

## York Factory deployment

Production currently predates the institution-ontology tables. Deploy in two
York steps: merge and deploy PR #111 first, initialize the checksummed source
release through its recipe, then run the read-only migration preflight:

```sh
bin/rails runner script/preflight_municipal_financial_migrations.rb
```

Only after that succeeds should the stacked York Factory PR merge and deploy:

```sh
bin/kamal deploy
bin/kamal app exec --reuse 'bin/rails db:migrate:status'
```

The web entrypoint runs `db:prepare`, so migrations execute as the new container
starts. The seven municipal migrations are additive except for replacing
extraction and line-item unique indexes and adding validated check constraints.
The constraints are added `NOT VALID` and then validated to avoid taking the
strongest table lock for the scan. Keep the API unreferenced by CanadaSpends
until migrations and data promotion succeed.

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

Set the production server-side environment variable in the Cloudflare Workers
dashboard (and explicitly configure preview deployments rather than allowing
them to inherit an accidental origin):

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
- If a data payload is wrong, disable the frontend route, retain the import
  audit, and promote a corrected, superseding dated release. The current release
  model has no unpublished state. Do not mutate the immutable R2 key or erase
  failed test evidence.
