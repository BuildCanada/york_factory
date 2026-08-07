# York Factory Public API

Read-only, JSON-over-HTTP. CORS-enabled (see `CORS_ORIGINS` env var). No authentication required for read endpoints; write endpoints are token-authenticated and documented per-resource.

## Base URL

- Production: `https://api.buildcanada.com`
- Development: `http://localhost:3000`

All endpoints are under `/api/v1/`.

## Conventions

### Pagination

Index endpoints return `{ data: [...], meta: { page, pages, count, per_page } }`. Override default page size with `?per_page=N` (capped reasonably per endpoint — typically 100). Override page with `?page=N`.

### Error responses

Standard JSON envelope:

```json
{ "error": "not_found", "details": "optional context" }
```

HTTP status codes:
- `200` — success
- `404` — resource not found (e.g., unknown slug)
- `422` — validation error on a write endpoint
- `401` — missing/invalid bearer token (admin write endpoints)
- `403` — token lacks required scope (admin write endpoints)

### Date / time

ISO 8601. `published_at` and similar are dates (`YYYY-MM-DD`); `started_at`, `created_at`, etc. include time + UTC.

### Identifiers

- **Surrogate IDs** (`id`) are bigserial integers, stable across requests.
- **Slugs** (`slug`) are stable, human-readable handles. Prefer slugs over IDs in URLs when both are documented.

## Sections

- **[KPIs](./kpis/README.md)** — Government performance indicators, source documents, and agent-run audit trail.
- **[Elections](./elections.md)** — Elections, races, and registered candidates (front-end spec).
- **[Ward lookup](./ward_lookup.md)** — Postal code → municipal ward, for "find your ward" inputs (front-end spec).

## Other public APIs

These live in the codebase but are documented elsewhere:

- `/api/v1/{posts,memos,builders,team,tools,faqs,feed,testimonials}` — CMS content.
- `/api/v1/geo/{boundaries,addresses,crosswalk}` — geographic boundaries and address lookup. (`geo/ward_lookup` is documented above.)
- `/api/v1/trade_barriers/{agreements,themes}` — Trade barriers tracker.
- `/api/v1/warehouse/jurisdictions` — Legacy list endpoint kept for trade-barriers backward compat. Prefer `/api/v1/kpis/jurisdictions` going forward.
