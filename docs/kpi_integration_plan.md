# KPI Integration Plan — toronto-budgets → York Factory

## Why this lives in York Factory, not toronto-budgets

The toronto-budgets `schema_v2_plan.md` redesigns a *SQLite* analytical store for one government (City of Toronto). York Factory already solves three of the problems that plan defers, so we should land KPIs here instead of finishing v2 there:

- **Multi-government from day one.** `warehouse.jurisdictions` exists (trade barriers seeded federal + 13 provincial/territorial rows). The v2 plan's `governments` table is redundant here; it's a column rename + a few fiscal-calendar fields.
- **Entity resolution already cascades.** `Warehouse::Organization::EntityResolver` is the exact mechanism the v2 plan's `agency_aliases` + manual mapping step needs, plus an LLM fuzzy tier and a `lineage_entries` audit table.
- **Ingestion lineage is a first-class pattern.** `Source::Fetcher → RawIngestion::*Loader` (`active_record-associated_object`) gives PDF documents + page citations a natural home with auditable raw-file archival to R2.
- **Postgres, not SQLite.** Drops the v2 plan's `PRAGMA foreign_keys`, `GLOB`, `ROW_NUMBER() OVER` concerns; everything is standard. We also get JSONB for messy `notes` fields and proper enum constraints.

The dashboard at `toronto-budgets/dashboard` is the only consumer of `scrape.db`. After migration it reads from a York Factory API endpoint (new `/api/v1/kpis/*`), not SQLite.

## Scope of the integration

In scope:
1. Add KPI tables under `warehouse.*` (Postgres), modelled on v2 but reusing existing primitives.
2. One-time ETL from `toronto-budgets/scrape.db` SQLite → `warehouse.*` Postgres.
3. New `RawIngestion::KpiLoader` so future scrapes flow through the same `Source::Fetcher` pipeline.
4. Public read API endpoints for the dashboard.
5. Retire `scrape.db` as the analytical store; keep it as the scraper's state file only.

Out of scope (deferred, same list as v2):
- Inflation/deflator adjustments.
- Cross-government agency ontology mapping.
- Document deduplication across governments via `content_hash`.

## Schema mapping: v2 plan → York Factory `warehouse`

| v2 (SQLite) | York Factory (Postgres) | Action |
|---|---|---|
| `governments` | `warehouse.jurisdictions` | **Extend.** Add `fiscal_year_start_month`, `default_currency`, `slug`. Backfill Toronto + the 14 existing rows. |
| `agencies` | `warehouse.organizations` | **Extend.** Add `jurisdiction_id` FK (NOT NULL after backfill — existing rows get the federal jurisdiction), `slug`, `kind`, `parent_organization_id`, `active_from_year`, `active_to_year`, `description`. `canonical_name` already exists. |
| `agency_aliases` | `warehouse.organization_aliases` | **Reuse as-is.** Add `alias_norm` generated column on `lower(unaccent(alias))` for index lookups. |
| `agency_lineage` | `warehouse.organization_lineages` (new) | **New table.** Pred/succ FK to `organizations`, `transition_year`, `transition_kind` enum, `acknowledged_in_document_id`, `notes`. Don't reuse `lineage_entries` — that one is per-ingestion provenance, a different concern. |
| `units` | `warehouse.units` (new) | **New table.** As v2 spec'd: `symbol`, `kind`, `base_unit`, `scale`, `currency_code`, `denominator_unit`, `denominator_scale`. |
| `documents` | `warehouse.kpi_documents` (new) | **New table.** Separate from `raw_ingestions` because these are *cited* PDFs (one row per published budget doc), not per-fetch ingestion runs. Each `kpi_document` belongs to a `raw_ingestion` (the scrape that found it) and a `jurisdiction`. |
| `measures` | `warehouse.measures` (new) | New. `organization_id` FK (NULL = cross-agency), `slug`, `canonical_name`, `unit_id`, `service_category`, `description`, `first_seen_year`, `last_seen_year`. |
| `measure_lineage` | `warehouse.measure_lineages` (new) | New, mirrors `organization_lineages`. |
| `measure_citations` | `warehouse.measure_citations` (new) | New. As v2 spec'd; `value_type` and `period_basis` as Postgres `CHECK` enums. |
| `measure_facts` VIEW | `warehouse.measure_facts` VIEW | New, identical window-function form. Promote to a materialized view if the dashboard exceeds ~500ms. |

### Naming/structural deltas from the v2 plan
- **`governments` → `jurisdictions`.** The trade-barriers tables already use this name and it's broader (works for crown corps, authorities).
- **`agencies` → `organizations`.** Already the canonical noun in York Factory. The Toronto KPI domain calls them "agencies/departments"; the Estimates domain calls them "organizations". Keep one name.
- **`lineage_entries` is *not* `organization_lineages`.** The existing `lineage_entries` table records per-ingestion entity-resolution decisions ("we matched 'Public Health' via LLM fuzzy match in run #42"). Agency renames/merges are a different shape — they're temporal facts, not provenance — so they get their own table.
- **`documents` collides** with the future possibility of a generic documents table. Namespace as `kpi_documents`. (If a generic `warehouse.documents` ever materializes, this gets renamed in a follow-up — no schema lock-in.)

## Migration phases

### Phase 0 — Snapshot
- `cp toronto-budgets/scrape.db toronto-budgets/scrape.db.pre-yf.bak`.
- Take a Supabase backup before running the import.

### Phase 1 — Schema migrations
Five migrations in one PR. Keep them small and ordered:

1. `add_kpi_fields_to_jurisdictions` — `slug`, `fiscal_year_start_month`, `default_currency`. Backfill `default_currency='CAD'` for all rows. Backfill `fiscal_year_start_month=4` for federal/provincial, `=1` for municipal (only Toronto exists today).
2. `add_kpi_fields_to_organizations` — `jurisdiction_id` (FK), `slug`, `kind`, `parent_organization_id`, `active_from_year`, `active_to_year`, `description`. Backfill `jurisdiction_id` on existing federal rows by joining via a seed; add NOT NULL afterward.
3. `create_warehouse_organization_lineages` — pred/succ FKs, transition_year, transition_kind enum, acknowledged_in_document_id (nullable, FK added later in step 5), notes.
4. `create_warehouse_units_and_measures` — both `units` and `measures` (measures needs units).
5. `create_warehouse_kpi_documents_and_citations` — `kpi_documents`, `measure_citations`, `measure_lineages`; add the deferred FK from `organization_lineages.acknowledged_in_document_id` → `kpi_documents.id`.

Plus a sixth migration creating the `warehouse.measure_facts` view. Use `Scenic` if we want versioned views, otherwise raw SQL with `CREATE OR REPLACE VIEW` in `change_table`.

### Phase 2 — Seed reference data
A new Rake task `kpis:seed_reference` that runs idempotently:

- Upsert the Toronto jurisdiction (`slug: 'toronto'`, level `municipal`, `region_code: 'ON'`, fiscal year start month `1`).
- Read `scrape.db kpis.agency_department` distinct list (53 rows) → upsert into `warehouse.organizations` with `jurisdiction_id` = Toronto's id and assigned slugs. Hand-resolve the 16 known equivalence pairs from the v2 plan in a YAML fixture (`db/seeds/kpis/toronto_organizations.yml`) so the resolution is checked in.
- Read `scrape.db documents.agency_department` distinct → upsert into `warehouse.organization_aliases`. Use the existing `Organization::EntityResolver` cascade (exact → case-insensitive → encoding-normalized → LLM fuzzy ≥ 0.8) for anything not covered by the YAML; flag the rest for review in `lineage_entries`.
- Seed `warehouse.organization_lineages` from the documented Toronto transitions in the v2 plan (CTT→TO Live 2020, FREEE→CREM 2019, SSHA split 2024, OEM→TEM 2023, I&T→TSD 2022, AHO→Housing Secretariat 2020). YAML fixture, same pattern.
- Seed `warehouse.units` — hand-classified YAML for all 53 distinct unit strings from `scrape.db kpis.unit`. This stays the bottleneck the v2 plan identified; it has to be done once and the file checked in.

### Phase 3 — One-time SQLite → Postgres import
A `RawIngestion::TorontoKpisV1Loader` (one-shot) that reads `scrape.db` directly via the `sqlite3` gem and writes to Postgres. Wrap in a single Postgres transaction. Idempotent by `(jurisdiction_id, doc_url)` for documents and the v2 unique keys for measures/citations.

Steps inside the loader, in order:
1. **Documents.** `INSERT INTO warehouse.kpi_documents` from `scrape.db documents`. Resolve `organization_id` via aliases (NULL when unresolvable). Extract `published_at` from PDF metadata (`pdfinfo` on the R2-archived file; we have all 1,068). Fall back to `discovered_at` with `published_at_source='discovered_at_fallback'`. Compute SHA-256 `content_hash`.
2. **Measures.** From `scrape.db kpis`. Resolve `unit_id` via the seeded units table (lookup by `symbol`, default to `count`). Slug via `parameterize`.
3. **Citations.** From `scrape.db kpi_values`. Normalize `value_numeric` by `unit.scale`. Set `period_basis='full_year'` for all; Phase 3.5 overrides.
4. **Percentage cleanup.** For measures whose unit `kind='ratio'`, multiply `value_numeric` by 100 for the ~127 known fractional-bug rows (`value_numeric < 1 AND > 0`); flag in `notes`.
5. **Measure lineage.** Load from a YAML fixture distilled from `kpis.description` and `kpi_values.notes` (EDC reframe, Children's Services, TPL, Shelter/Housing, etc.) — same set the v2 plan enumerated.

Run from a Rake task: `bin/rails kpis:import_toronto_v1[/path/to/scrape.db]`. Mark the resulting `RawIngestion` row with `source.name='toronto-budgets-v1-snapshot'` so it's clearly a one-shot, not a recurring ingestion.

### Phase 3.5 — LLM-classify `period_basis` (no human in the loop)
The candidate set (same query the v2 plan proposed, now in Postgres):

```sql
SELECT id, measurement_year, value_type, document_id, value_numeric, notes
FROM warehouse.measure_citations
WHERE notes ~* '\m(ytd|year-to-date|as of|cumulative|partial|q[1-3])\M';
```

Classifier is `Warehouse::MeasureCitation::PeriodBasisClassifier` (Claude Haiku 4.5 via `ruby_llm`, the same model `EntityResolver` uses). It batches 10 rows per LLM call, classifies into one of five labels, returns `{period_basis, confidence, reasoning}` per row.

```bash
bin/rails kpis:classify_period_basis
# → auto-applies labels at confidence >= 0.8; writes an audit CSV with every
#   row's proposal + reasoning + whether it was applied
```

For 183 candidates this is ~19 API calls (~$0.01 of Haiku). Real run yielded:
- 132 auto-applied (103 ytd_q3, 25 as_of_date, 3 ytd_q1, 1 ytd_q2)
- 35 confirmed as full_year (no change needed)
- 16 below 0.8 confidence — surface in the audit CSV for spot-check via `kpis:apply_period_basis_from_audit[/path/to/audit.csv]` after editing `applied=true`.

The human-labeling CSV pair (`kpis:export_period_basis_candidates` / `kpis:apply_period_basis`) stays as a fallback for when the LLM is unavailable or for deliberate human override.

### Phase 4 — Verify
- `Warehouse::Measure.count == sqlite3('SELECT COUNT(*) FROM kpis')` — 1,206.
- `Warehouse::MeasureCitation.count == sqlite3('SELECT COUNT(*) FROM kpi_values')` — 20,895.
- `Warehouse::KpiDocument.count == 1,068`.
- 20-row spot-check fixture: pick 20 (measure, year, value_type) tuples by hand from `scrape.db`, assert each round-trips through `Warehouse::MeasureFact`.
- Test coverage: model tests for each new model; integration test for `TorontoKpisV1Loader` using a tiny fixture SQLite file in `test/fixtures/files/`.

### Phase 5 — Public API
New controllers under `Api::V1::Kpis::*`:

- `GET /api/v1/kpis/jurisdictions` — list.
- `GET /api/v1/kpis/jurisdictions/:slug/organizations` — list with lineage.
- `GET /api/v1/kpis/organizations/:slug/measures` — list with units.
- `GET /api/v1/kpis/measures/:id/facts` — resolved facts from the view (paginated, filterable by year, value_type).
- `GET /api/v1/kpis/measures/:id/citations` — all citations for audit.

Serializers in the existing `app/serializers/api/v1` style. Public (no auth), CORS-enabled per existing `CORS_ORIGINS` setup.

### Phase 6 — Dashboard cutover + scraper retargeting
- Repoint `toronto-budgets/dashboard` from `scrape.db` to the new API. Done in the toronto-budgets repo; out of scope for the York Factory PR but tracked as a follow-up.
- Update the `toronto-budget-kpis` skill so future per-agency extractions write via a new `Warehouse::RawIngestion::KpiLoader` (Postgres) instead of directly into `scrape.db`. The skill currently calls Python `insert_*_kpis.py` scripts; those become thin clients of the York Factory admin API (`POST /admin/kpis/citations`) or the loader is invoked directly via a Rake task.
- `scrape.db` is retained but demoted: it stays the scraper's *crawl state* (page URLs, fetch status, HTTP errors). The analytical tables (`kpis`, `kpi_values`, the v2 `measure_*`) are no longer written to it. Rename them `_v1_kpis` etc. in the toronto-budgets repo as the v2 plan already prescribed.

## What requires human judgment (unchanged from v2 plan)

| Task | Where it lives in York Factory | Effort |
|---|---|---|
| 16 string-equivalent agency pairs | `db/seeds/kpis/toronto_organizations.yml` | ~1h |
| 53 unit classifications | `db/seeds/kpis/units.yml` | ~1h |
| Organization lineage rows | `db/seeds/kpis/toronto_organization_lineages.yml` | ~20m |
| Measure lineage rows | `db/seeds/kpis/toronto_measure_lineages.yml` | ~2h |
| PDF `published_at` extraction + audit | Rake task `kpis:backfill_published_at` | ~1h |
| `period_basis` classification | LLM-driven via `kpis:classify_period_basis` (Haiku 4.5) | ~5min compute, ~5min review of below-threshold rows |

Total ~7-8h human + 1-2h scripts (same as v2). The work moves into checked-in YAML fixtures so it's reviewable and replayable, rather than living in a one-off migration.

## Rollback

- Each migration has a clean `down`. Run them in reverse to undo.
- The one-time import is a single transaction; rollback drops the inserted rows by `raw_ingestion_id`.
- `scrape.db.pre-yf.bak` from Phase 0 is the canonical safety net.
- Supabase point-in-time restore is the disaster fallback.

## Resolved decisions

1. **Views = inline SQL in migrations.** Match the `spending_deviations` precedent. No Scenic. `CREATE OR REPLACE VIEW warehouse.measure_facts` lives directly in the migration.
2. **Admin write API is in scope.** An AI agent will be the primary writer for new KPIs going forward (replacing the per-agency `insert_*_kpis.py` scripts). Endpoints are token-authenticated (new `api_tokens` table or reuse Devise JWT — see admin API section below), idempotent on natural keys, and accept bulk citations in one request.
3. **`organizations.jurisdiction_id` is NOT NULL.** Backfill federal rows to the federal jurisdiction, add NOT NULL in the same migration. No nullable interim state.
4. **Lineage UNIQUE constraint:** keep v2's `(predecessor_id, successor_id, transition_year, transition_kind)`. This is correct for M-to-1 merges (multiple rows share `successor_id` but differ on `predecessor_id`), 1-to-M splits (vice versa), revivals (different `transition_year`), and concurrent rename+methodology-revision (different `transition_kind`). The constraint *prevents* nonsense duplicates (same pred+succ+year+kind asserted twice) without blocking any real-world shape we know about.

## Admin write API (added)

Powers an AI agent that extracts KPIs from new budget PDFs.

Authentication: simple bearer token in `Authorization: Bearer <token>` against a new `warehouse.api_tokens` table (`name`, `token_hash`, `scopes`, `last_used_at`, `revoked_at`). Scopes are coarse: `kpis:read`, `kpis:write`. Tokens issued by hand via Rails console for now; the agent has its own token. Cheaper than wiring a second Devise scope and sufficient for an internal write surface.

Endpoints (all under `/api/v1/admin/kpis/`):

- `POST /documents` — idempotent upsert by `doc_url`. Returns document id.
- `POST /measures` — idempotent upsert by `(organization_id, slug)`. Accepts `unit_symbol` (resolves to `unit_id`); errors if symbol is unknown rather than auto-creating units (units stay human-curated).
- `POST /citations` — bulk insert (array body). Idempotent on the v2 unique key `(measure_id, measurement_year, value_type, period_basis, document_id)`. Returns counts: `inserted`, `skipped_duplicate`.
- `POST /organization_lineages` / `POST /measure_lineages` — idempotent upsert on their respective unique keys.

All write endpoints wrap in a transaction. All returns include the natural key and the surrogate id so the agent can chain calls without round-tripping.

## PR breakdown

Suggested split (1 PR per phase, mergeable independently after phase 1):

1. Schema migrations + models (no data movement) — reviewable, deployable, no behavior change.
2. Seed reference data + entity resolution wiring.
3. `TorontoKpisV1Loader` + one-time Rake task. Run in production once, then the task stays as a re-runnable backstop.
4. Phase 3.5 period_basis CSV import.
5. Public API + serializers + request specs.
6. (toronto-budgets repo) Dashboard cutover.
