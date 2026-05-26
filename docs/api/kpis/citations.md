# Citations

A citation is one observed value of one measure in one source document. It is the *atomic* unit of the dataset — every fact in the system traces to one or more citations.

For the resolved canonical-value view, see [facts.md](./facts.md) instead.

## `GET /api/v1/kpis/citations` (top-level)

**Query parameters:**
| Param | Description |
|---|---|
| `measure_id` | One measure. |
| `jurisdiction_slug` | All citations under one jurisdiction. |
| `organization_slug` | All citations under one org. |
| `document_id` | Every citation from one source doc. |
| `year` | One `measurement_year`. |
| `value_type` | `actual`, `target`, `projected`, `plan`, `budget`. |
| `period_basis` | `full_year`, `ytd_q1`, `ytd_q2`, `ytd_q3`, `as_of_date`. |
| `agent_run_id` | Every citation written by one agent run. |
| `per_page` | Default 100. |

## `GET /api/v1/kpis/measures/:measure_id/citations` (nested)

Same response shape, scoped to one measure. Use for a per-measure audit drill-down.

**Response:**
```json
{
  "data": [
    {
      "id": 41794,
      "measure_id": 2414,
      "measurement_year": 2025,
      "value_type": "target",
      "period_basis": "full_year",
      "value_numeric": 62.0,
      "value_text": null,
      "value_raw_text": "$62 billion",
      "page_number": null,
      "notes": "Target date: March 2025",
      "agent_run_id": 2,
      "document": {
        "id": 2139,
        "fiscal_year": 2025,
        "published_at": null,
        "doc_url": "https://www.canada.ca/en/canadian-heritage/.../departmental-results-report-2024-2025.html",
        "doc_title": "Canadian Heritage 2024-25 Departmental Results Report"
      }
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 162, "per_page": 100 }
}
```

## Fields

| Field | Type | Description |
|---|---|---|
| `id` | integer | Surrogate ID. |
| `measure_id` | integer | FK to the measure. |
| `measurement_year` | integer | Year the value pertains to. |
| `value_type` | string | `actual` / `target` / `projected` / `plan` / `budget`. |
| `period_basis` | string | `full_year` (default) or one of the YTD/snapshot variants. |
| `value_numeric` | float \| null | Numeric in the measure's unit (e.g., `65.3` for `$B`). |
| `value_text` | string \| null | Qualitative value (for `pass/fail`, `text`, `date` units). |
| `value_raw_text` | string \| null | Original PDF/HTML cell text before any normalization (audit trail). |
| `page_number` | integer \| null | Physical PDF page index (1-based) where the value was found. NULL for HTML sources. |
| `notes` | string \| null | Free-text caveats, methodology footnotes, etc. |
| `agent_run_id` | integer \| null | The `agent_runs` row that produced this citation. NULL for bulk-imported pre-agent data. |
| `document` | object | Source doc summary. |

## Why duplicate citations exist (and why that's good)

A 2025 Departmental Results Report citing a 2023 actual produces a citation. The same 2023 actual might also appear in:
- The 2024 DRR (the originating doc).
- A 2026 DRR restating the figure (e.g., "2023-24 actual restated from 122 to 149 due to methodology change").

All three citations are stored. The `measure_facts` view picks the latest as canonical, but the full history stays in `/citations` for audit, methodology research, and restatement-detection workflows.

To see the restatement timeline for one fact:

```bash
curl 'http://localhost:3000/api/v1/kpis/citations?measure_id=2414&year=2024&value_type=actual'
# → multiple rows; sort by document.published_at to see the chronology
```
