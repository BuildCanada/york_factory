# Documents

A document is a source artifact — a PDF budget note, HTML Departmental Results Report, annual report, etc. — that one or more citations were extracted from.

## `GET /api/v1/kpis/documents`

List documents, paginated.

**Query parameters:**
| Param | Description |
|---|---|
| `jurisdiction_slug` | Restrict to one jurisdiction. |
| `organization_slug` | Restrict to docs filed by/about one org. |
| `fiscal_year` | One fiscal year. |
| `published_after` | ISO date (`YYYY-MM-DD`). Inclusive. |
| `published_before` | ISO date. Inclusive. |
| `q` | Substring match on `doc_title` and `doc_url`. Case-insensitive. |
| `per_page` | Default 50. |
| `page` | Default 1. |

**Example:**
```bash
curl 'http://localhost:3000/api/v1/kpis/documents?organization_slug=canadian-heritage&fiscal_year=2025'
```

**Response:**
```json
{
  "data": [
    {
      "id": 2139,
      "doc_url": "https://www.canada.ca/en/canadian-heritage/corporate/publications/plans-reports/departmental-results-report-2024-2025.html",
      "doc_title": "Canadian Heritage 2024-25 Departmental Results Report",
      "doc_type": "departmental_results_report",
      "fiscal_year": 2025,
      "published_at": null,
      "published_at_source": "manual",
      "content_hash": null,
      "jurisdiction": { "id": 1, "slug": "ca", "name": "Canada" },
      "organization": { "id": 60, "slug": "canadian-heritage", "canonical_name": "Canadian Heritage" }
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "per_page": 50 }
}
```

Default sort is `published_at DESC NULLS LAST, fiscal_year DESC, id DESC` so the most recent docs come first.

## `GET /api/v1/kpis/documents/:id`

Show one document with rollup counts.

**Response (additions over the index):**
```json
{
  "citation_count": 162,
  "measure_count": 41
}
```

- `citation_count` — total citations extracted from this document.
- `measure_count` — distinct measures cited by this document.

## Fields

| Field | Type | Description |
|---|---|---|
| `id` | integer | Surrogate ID. |
| `doc_url` | string | Canonical source URL. Unique across the dataset. |
| `doc_title` | string \| null | Display title. |
| `doc_type` | string \| null | Free-text classifier — e.g., `departmental_results_report`, `departmental_plan`, `operating_budget_note`, `briefing_note`, `annual_report`. |
| `fiscal_year` | integer | The fiscal year the document covers (publication year, not measurement year). |
| `published_at` | date \| null | Publication date, if known. |
| `published_at_source` | string \| null | How `published_at` was determined: `pdf_metadata`, `http_last_modified`, `council_schedule`, `discovered_at_fallback`, `manual`. The `measure_facts` view ranks `pdf_metadata`-sourced docs higher than `discovered_at_fallback`. |
| `content_hash` | string \| null | SHA-256 of the file body when archived. |
| `jurisdiction` | object | Owning jurisdiction. |
| `organization` | object \| null | The org the doc is *about*. May be null if the doc is cross-agency (e.g., a city-wide budget overview). |

## Common workflows

**Find every measure cited by a doc:**
```bash
curl 'http://localhost:3000/api/v1/kpis/citations?document_id=2139' \
  | jq '[.data[].measure_id] | unique'
```

**Drill from a fact back to its source PDF:**
```bash
# Get the fact → get the citation → get the document
FACT=$(curl -s 'http://localhost:3000/api/v1/kpis/measures/2414/facts?year=2025&value_type=actual')
CITATION_ID=$(echo "$FACT" | jq '.data[0].citation_id')
DOC_ID=$(echo "$FACT" | jq '.data[0].document_id')
curl "http://localhost:3000/api/v1/kpis/documents/$DOC_ID"
```
