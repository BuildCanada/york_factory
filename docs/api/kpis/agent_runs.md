# Agent runs

Every API-driven write to the warehouse is tagged with an `agent_run_id` — a row in `warehouse.agent_runs` that records who ran what, when, with what inputs, and with what result. This applies to KPI extractions (the `extract-kpis` skill) and any future agents that write through the admin API.

A run has a lifecycle:

```
created (status='running', started_at=NOW)
   ↓
admin POSTs documents/measures/citations stamped with agent_run_id
   ↓
PATCH /admin/agent_runs/:id { status: 'completed', report, summary }
   ↓
finished_at auto-stamped
```

## `GET /api/v1/kpis/agent_runs`

List runs, paginated. The `report` body is omitted from the index (it can be long).

**Query parameters:**
| Param | Description |
|---|---|
| `agent` | Filter by `agent_name`. |
| `status` | One of `running`, `completed`, `failed`, `cancelled`. |
| `per_page` | Default 50. |

**Response:**
```json
{
  "data": [
    {
      "id": 2,
      "agent_name": "extract-kpis",
      "agent_version": "fdb8636",
      "status": "completed",
      "input_params": {
        "doc_url": "https://www.canada.ca/.../departmental-results-report-2024-2025.html",
        "fiscal_year": 2025,
        "jurisdiction_slug": "ca",
        "organization_slug": "canadian-heritage"
      },
      "summary": {
        "documents": 1,
        "measures_created": 41,
        "citations_inserted": 162,
        "core_responsibilities_covered": 5
      },
      "triggered_by": "extract-kpis",
      "started_at": "2026-05-25T23:26:55.012Z",
      "finished_at": "2026-05-25T23:30:08.542Z",
      "error_message": null
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 2, "per_page": 50 }
}
```

## `GET /api/v1/kpis/agent_runs/:id`

Show one run including the full `report` markdown.

**Response (additions over the index):**
```json
{
  "report": "# Canadian Heritage (Federal Canada) — FY 2024-25 KPI extract\n\nSource: …\n\n## Headline findings\n…"
}
```

The `report` is freeform markdown — typically a per-org summary of what was extracted with headline findings, year-by-year tables, methodology shifts, and gaps. Render with any standard markdown renderer.

## Fields

| Field | Type | Description |
|---|---|---|
| `id` | integer | Surrogate ID. |
| `agent_name` | string | Logical agent identifier — `extract-kpis`, future agents will have their own. |
| `agent_version` | string \| null | Freeform — typically a git short-SHA for repo-tracked skills. |
| `status` | string | `running`, `completed`, `failed`, `cancelled`. |
| `input_params` | object (JSONB) | The exact parameters the agent was invoked with. |
| `summary` | object (JSONB) \| null | Structured counts the agent reports on completion. |
| `triggered_by` | string | API token name that opened the run. |
| `started_at` | timestamp | When the run was opened. |
| `finished_at` | timestamp \| null | When the run reached a terminal state. |
| `error_message` | string \| null | Set when `status='failed'`. |
| `report` | string \| null | (Show only.) Markdown narrative report from the agent. |

## Cross-referencing

Every write stamps its `agent_run_id`. Find everything one run produced:

```bash
# Documents created by run 2
curl 'http://localhost:3000/api/v1/kpis/documents' | jq '.data[] | select(.agent_run_id == 2)'
# (no top-level filter for documents by agent_run yet — see Gaps below)

# Citations stamped to run 2
curl 'http://localhost:3000/api/v1/kpis/citations?agent_run_id=2'
```

## Why this exists

Two reasons:

1. **Audit trail.** Every value in the dataset can be traced back to (a) a source document and (b) the agent run that extracted it. If a value looks wrong, you can read the `report` to see what the agent thought it was doing.
2. **Replay safety.** Re-running the same extraction creates a new run row. The underlying writes are idempotent on natural keys (doc_url, measure slug, citation tuple), so a re-run typically results in `citations_inserted: 0, skipped_duplicate: N`. The agent_run row still gets created so the history of *attempts* is preserved separately from the history of *changes*.

## Gaps

- No top-level filter for documents by `agent_run_id` (it's a column on the row but not exposed in the documents index). File an issue if you need it.
- No bulk "show me the full lineage of this row" endpoint — currently a multi-step crawl.
