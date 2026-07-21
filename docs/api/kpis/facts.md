# Facts

A *fact* is the canonical resolved value for a `(measure, measurement_year, value_type, period_basis)` tuple. Multiple documents may cite the same fact with different values (restatements); the `warehouse.measure_facts` Postgres view picks one as authoritative using a deterministic tiebreak:

1. Highest `published_at` on the source document (NULLs last).
2. Highest `fiscal_year` on the source document.
3. Highest citation `id`.

For the raw "every observation we've ever seen" view, use [citations.md](./citations.md) instead.

## `GET /api/v1/kpis/facts` (top-level, cross-measure)

**Query parameters:**
| Param | Description |
|---|---|
| `measure_id` | One measure's facts. |
| `jurisdiction_slug` | All facts for orgs in this jurisdiction. |
| `organization_slug` | All facts for this org. Pair with `jurisdiction_slug` when organization slugs are not globally unique. |
| `year` | One `measurement_year`. |
| `value_type` | One of `actual`, `target`, `projected`, `plan`, `budget`. |
| `period_basis` | One of `full_year`, `ytd_q1`, `ytd_q2`, `ytd_q3`, `as_of_date`, `month`. |
| `per_page` | Default 100. |

## `GET /api/v1/kpis/measures/:measure_id/facts` (nested)

Same response shape as the top-level endpoint, scoped to one measure. Use this for a measure-detail page.

**Response:**
```json
{
  "data": [
    {
      "measure_id": 2414,
      "measurement_year": 2025,
      "value_type": "actual",
      "period_basis": "full_year",
      "value_numeric": 65.3,
      "value_text": null,
      "citation_id": 41797,
      "document_id": 2139
    },
    {
      "measure_id": 2414,
      "measurement_year": 2025,
      "value_type": "target",
      "period_basis": "full_year",
      "value_numeric": 62.0,
      "value_text": null,
      "citation_id": 41794,
      "document_id": 2139
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 4, "per_page": 100 }
}
```

## Fields

| Field | Type | Description |
|---|---|---|
| `measure_id` | integer | FK to the measure. |
| `measurement_year` | integer | The year the value pertains to. Note: federal `YYYY-YY` fiscal years use the *end* year (e.g., `2024-25` → `2025`). |
| `value_type` | string | `actual`, `target`, `projected`, `plan`, `budget`. |
| `period_basis` | string | `full_year`, `ytd_q1`, `ytd_q2`, `ytd_q3`, `as_of_date`, `month`. Defaults to `full_year`. |
| `value_numeric` | float \| null | Numeric value in the measure's unit. For qualitative measures (`pass/fail`, `text`, `date`) this is null. |
| `value_text` | string \| null | Used for qualitative measures. |
| `citation_id` | integer | The underlying canonical citation. Cross-reference with `/citations`. |
| `document_id` | integer | The source doc the canonical citation came from. Cross-reference with `/documents`. |

## When citations and facts disagree

If `/citations` returns 3 rows for `(measure_id=2414, year=2025, value_type=actual, period_basis=full_year)` but `/facts` returns only 1, that's expected — the view dedupes. The two sibling citations represent earlier reports of the same fact that were superseded. To see the resolution history for an indicator, query `/citations` directly and sort by `document.published_at DESC`.
