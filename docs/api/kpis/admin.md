# Admin write API

Write endpoints for the KPI dataset. Used by Claude Code skills (e.g., `extract-kpis`) and any other agent that ingests KPIs.

## Authentication

Bearer token in the `Authorization` header. Tokens are issued via Rails console / Rake task on the York Factory side:

```bash
bin/rails kpis:issue_token name=my-agent
# → yfk_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345678
```

Every request:
```
Authorization: Bearer yfk_…
Content-Type: application/json
```

Tokens have scopes. The `kpis:write` scope is required for every endpoint below. Missing/invalid token returns `401`; valid token without the required scope returns `403`.

## Idempotency

Every endpoint is idempotent on a natural key:

| Endpoint | Natural key |
|---|---|
| `/organizations` | `(jurisdiction_slug, slug)` |
| `/documents` | `doc_url` |
| `/measures` | `(organization_slug, slug)` |
| `/citations` | `(measure_id, measurement_year, value_type, period_basis, document_id)` |
| `/organization_lineages` | `(predecessor_id, successor_id, transition_year, transition_kind)` |
| `/measure_lineages` | same |
| `/agent_runs` | none — every call creates a new row |

Re-posting the same payload returns the existing row's id (with `created: false` where the response exposes it).

## Audit trail

Most write endpoints accept an `agent_run_id` field that stamps the produced row(s). Callers should:

1. `POST /agent_runs` to open a run.
2. Pass the returned id on every subsequent write.
3. `PATCH /agent_runs/:id` to close the run with `status` + `report` + `summary`.

See [agent_runs.md](./agent_runs.md) for details.

## Endpoints

### `POST /api/v1/kpis/admin/organizations`

Idempotent on `(jurisdiction_slug, slug)`.

```json
{
  "organization": {
    "jurisdiction_slug": "ca",
    "slug": "department-of-x",
    "canonical_name": "Department of X",
    "kind": "department",
    "description": "...",
    "parent_organization_slug": "...",
    "active_from_year": 2020,
    "active_to_year": null,
    "aliases": ["DX", "Dept of X"],
    "agent_run_id": 47
  }
}
```

**Response:**
```json
{ "id": 60, "slug": "department-of-x", "canonical_name": "Department of X",
  "jurisdiction_id": 1, "created": true }
```

`canonical_name` is always auto-registered as an alias. Subsequent calls with new `aliases[]` entries upsert them without duplicating existing ones.

### `POST /api/v1/kpis/admin/documents`

Idempotent on `doc_url`.

```json
{
  "document": {
    "jurisdiction_slug": "ca",
    "organization_slug": "canadian-heritage",
    "fiscal_year": 2025,
    "doc_url": "https://.../report.html",
    "doc_title": "...",
    "doc_type": "departmental_results_report",
    "published_at": "2025-03-31",
    "published_at_source": "manual",
    "source_page_url": "https://.../parent-listing-page",
    "content_hash": "sha256-…",
    "agent_run_id": 47
  }
}
```

`published_at_source` is one of `pdf_metadata`, `http_last_modified`, `council_schedule`, `discovered_at_fallback`, `manual`. The `measure_facts` resolution view ranks `pdf_metadata` > others.

**Response:** `{ id, doc_url, fiscal_year, jurisdiction_id, organization_id, published_at, published_at_source }`.

### `POST /api/v1/kpis/admin/measures`

Idempotent on `(organization_slug, slug)`.

```json
{
  "measure": {
    "organization_slug": "canadian-heritage",
    "slug": "gdp-of-the-canadian-cultural-sector",
    "canonical_name": "GDP of the Canadian cultural sector",
    "unit_symbol": "$B",
    "service_category": "Creative industries…",
    "description": "...",
    "first_seen_year": 2020,
    "last_seen_year": 2025,
    "agent_run_id": 47
  }
}
```

**`unit_symbol` must already exist in `warehouse.units`.** If unknown, the API returns `422 { "error": "unknown_unit", "hint": "Add the unit symbol to db/seeds/kpis/units.yml and reseed" }`. This is deliberate — unit definitions are human-curated to keep the catalog consistent.

**Response:** `{ id, slug, canonical_name, organization_id, unit_id }`.

### `POST /api/v1/kpis/admin/citations`

Bulk insert. Top-level `agent_run_id` stamps every row in the batch. Idempotent on the v2 unique key.

```json
{
  "agent_run_id": 47,
  "citations": [
    {
      "measure_id": 5678,
      "measurement_year": 2024,
      "value_type": "actual",
      "period_basis": "full_year",
      "value_numeric": 2.2,
      "value_text": null,
      "value_raw_text": "$2.2 billion",
      "document_id": 1234,
      "page_number": 5,
      "notes": "Methodology change: includes streaming."
    }
  ]
}
```

**Response:**
```json
{ "inserted": 47, "skipped_duplicate": 0, "ids": [41794, 41795, …] }
```

Use `value_text` for qualitative units (`pass/fail`, `text`, `date`). `value_raw_text` is the pre-normalization source text — leave as the exact PDF/HTML cell content.

**`value_numeric` must be in DISPLAY units, not base units.** For a measure with `unit_symbol: "$B"`, send `65.3` (not `65,300,000,000`). For `%`, send `90` (not `0.9`). The `unit.scale` exists so consumers can normalize for cross-unit math, but the canonical stored value is what a human would see on the page.

### `POST /api/v1/kpis/admin/organization_lineages`

Idempotent on `(predecessor_id, successor_id, transition_year, transition_kind)`.

```json
{
  "lineage": {
    "predecessor_slug": "shelter-support-and-housing-administration",
    "successor_slug": "toronto-shelter-and-support-services",
    "transition_year": 2024,
    "transition_kind": "split",
    "acknowledged_in_document_id": 1234,
    "notes": "SSHA → TSSS as part of 2024 housing reorg."
  }
}
```

For M-to-1 merges and 1-to-M splits, POST one row per pair. `transition_kind` must be one of `rename`, `merge`, `split`, `absorb`, `spin_off`, `revived`.

### `POST /api/v1/kpis/admin/measure_lineages`

Same shape, using `predecessor_id` and `successor_id` (measure IDs, not slugs).

`transition_kind` additions vs. organization lineages: `methodology_revision`, `unit_change`, `scope_change`.

### `POST /api/v1/kpis/admin/agent_runs`

Open a new run.

```json
{
  "agent_run": {
    "agent_name": "extract-kpis",
    "agent_version": "fdb8636",
    "input_params": { "fiscal_year": 2025, "organization_slug": "canadian-heritage" }
  }
}
```

`triggered_by` is set server-side to the API token name. `started_at` is set to `NOW()`.

### `PATCH /api/v1/kpis/admin/agent_runs/:id`

Close (or update) a run. Setting `status` to a terminal value (`completed`/`failed`/`cancelled`) auto-stamps `finished_at`.

```json
{
  "agent_run": {
    "status": "completed",
    "report": "# Extract complete\n\n…markdown body…",
    "summary": { "documents": 1, "citations_inserted": 162, "skipped_duplicate": 0 }
  }
}
```

### `GET /api/v1/kpis/admin/agent_runs/:id`

Same shape as the public `GET /api/v1/kpis/agent_runs/:id` but requires admin token. Useful when the agent itself wants to read back its own run row.

## Errors

| HTTP | Body | When |
|---|---|---|
| `401` | `{ "error": "unauthorized" }` | Missing or unknown bearer token. |
| `403` | `{ "error": "forbidden" }` | Token lacks `kpis:write` scope. |
| `404` | `{ "error": "not_found", "details": "..." }` | Referenced jurisdiction/org/document doesn't exist. |
| `422` | `{ "error": "validation_failed", "details": [...] }` | Model validation error. |
| `422` | `{ "error": "unknown_unit", "hint": "..." }` | `unit_symbol` not in `warehouse.units` (measures endpoint only). |
| `422` | `{ "error": "no_citations" }` | Empty `citations: []` array. |
