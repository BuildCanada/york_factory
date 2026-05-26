# KPIs API

Government performance indicators (KPIs) sourced from federal Departmental Plans / Results Reports, provincial Annual Business Plans / Reports, and municipal budget notes. Same schema applies across all three levels of government.

## Data model — at a glance

```
jurisdiction (federal CA, provincial AB/BC/…, municipal toronto, …)
  └── organization (Canadian Heritage, TTC, …)
        └── measure (an indicator — "GDP of cultural sector", "On-time bus performance")
              └── citation (one observed value from one source document)

document (a PDF or HTML report) — produces many citations across many measures

measure_facts (view) — the "canonical resolved value" per (measure, year, type, period)
                       deterministic tiebreak across competing citations
```

Two lineage tables capture renames/merges/methodology shifts:
- `organization_lineages` — pred → succ at a transition_year (rename, merge, split, absorb, spin_off, revived).
- `measure_lineages` — same shape, plus `methodology_revision`, `unit_change`, `scope_change`.

Every API-driven write is tagged with an `agent_run_id` so the source of any row in the system is auditable end-to-end.

## Endpoints — read (public)

| Resource | Endpoint | Doc |
|---|---|---|
| Jurisdictions | `GET /api/v1/kpis/jurisdictions` | [jurisdictions.md](./jurisdictions.md) |
| Organizations | `GET /api/v1/kpis/jurisdictions/:slug/organizations` | [organizations.md](./organizations.md) |
| Measures | `GET /api/v1/kpis/measures` | [measures.md](./measures.md) |
| Facts (resolved) | `GET /api/v1/kpis/facts` and nested under a measure | [facts.md](./facts.md) |
| Citations (raw) | `GET /api/v1/kpis/citations` and nested under a measure | [citations.md](./citations.md) |
| Documents | `GET /api/v1/kpis/documents` | [documents.md](./documents.md) |
| Organization lineages | `GET /api/v1/kpis/organization_lineages` | [lineages.md](./lineages.md#organization-lineages) |
| Measure lineages | `GET /api/v1/kpis/measure_lineages` | [lineages.md](./lineages.md#measure-lineages) |
| Agent runs | `GET /api/v1/kpis/agent_runs` | [agent_runs.md](./agent_runs.md) |

## Endpoints — write (admin)

Token-authenticated (`Authorization: Bearer yfk_…`), scope `kpis:write`. See [admin.md](./admin.md) for the full surface (organizations, documents, measures, citations, lineages, agent_runs).

## Quick examples

```bash
# Every 2024 actual measurement across all federal departments
curl 'http://localhost:3000/api/v1/kpis/facts?jurisdiction_slug=ca&year=2024&value_type=actual'

# Resolved facts for one measure, all years
curl 'http://localhost:3000/api/v1/kpis/measures/2414/facts'

# Every PDF/HTML report Canadian Heritage has filed since 2022
curl 'http://localhost:3000/api/v1/kpis/documents?organization_slug=canadian-heritage&published_after=2022-01-01'

# Renames/merges in Toronto's org tree
curl 'http://localhost:3000/api/v1/kpis/organization_lineages?jurisdiction_slug=toronto'

# Audit trail for a specific extraction run (includes the agent's markdown report)
curl 'http://localhost:3000/api/v1/kpis/agent_runs/2'
```

## Facts vs. citations — which to use

- **Facts** (`/facts` and `/measures/:id/facts`) are the *canonical* resolved values. One row per `(measure, year, value_type, period_basis)`. The latest published document wins. Use this for charts and dashboards.
- **Citations** (`/citations` and `/measures/:id/citations`) are the *raw observations* — every value ever cited from any document. Multiple rows for the same fact are normal and useful: they reveal restatements (a 2024 doc reporting "2021 actual: 5,921 — revised from 10,759" produces two citations and the view shows the newer one). Use this for audit, source-tracking, and methodology research.
