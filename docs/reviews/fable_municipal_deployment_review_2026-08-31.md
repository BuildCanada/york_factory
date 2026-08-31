# Fable review — municipal financial deployment

Claude Fable reviewed the two-repository release process on 2026-08-31 in the
`municipal-pr-deploy-fable-review` tmux session. The review covered both git
diffs, stacked PR ancestry, York's migrations and Kamal entrypoint, the immutable
release exporter, R2 assumptions, CanadaSpends runtime behavior, and rollback.

The review agreed with the parent-then-stack and York-before-CanadaSpends order,
but rejected the original data-promotion section as non-executable. In
particular:

- the existing ontology exporter omits detailed line items and census profiles;
- its SQL loader populates `public_institutions`, not the Rails `warehouse`
  tables queried by the API;
- no verified Warehouse importer or immutable R2 release uploader exists;
- the production deployment predates the ontology tables, so the source release
  must be initialized before detailed data can be imported;
- final evidence currently lives on `/Volumes/floppy` and must be uploaded with
  the immutable release before production promotion;
- the Rails container runs `db:prepare` on web boot, so constraint compatibility
  must be checked before the stacked York deploy;
- a bad release cannot currently be marked unpublished; correction requires
  disabling the frontend route and importing a superseding dated release.

Fable also identified shared CanadaSpends risks. The follow-up fixes preserve
declared Sankey denominators when present, promote compact currency values across
rounding boundaries, derive latest/earliest years without trusting API order, and
restore yearless municipal metadata/fallback behavior.

The revised deployment plan treats the verified importer, R2 uploader, frozen
audit artifact set, and migration preflight as hard gates. It explicitly rejects
whole-database copying and production re-extraction as promotion mechanisms.
