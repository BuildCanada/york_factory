# Jurisdictions

A jurisdiction is a level of government — federal Canada, a province or territory, or a municipality. Every organization belongs to exactly one jurisdiction.

## `GET /api/v1/kpis/jurisdictions`

List all jurisdictions.

**Request:**
```
GET /api/v1/kpis/jurisdictions
```

**Response:**
```json
{
  "data": [
    {
      "id": 1,
      "slug": "ca",
      "name": "Canada",
      "code": "CA",
      "level": "federal",
      "region_code": null,
      "fiscal_year_start_month": 4,
      "default_currency": "CAD"
    },
    {
      "id": 15,
      "slug": "toronto",
      "name": "City of Toronto",
      "code": "TOR-ON",
      "level": "municipal",
      "region_code": "ON",
      "fiscal_year_start_month": 1,
      "default_currency": "CAD"
    }
  ]
}
```

## `GET /api/v1/kpis/jurisdictions/:slug`

Show one jurisdiction.

**Path parameters:**
- `slug` — e.g., `ca`, `toronto`, `ab`.

**Response:** single jurisdiction object (same shape as in the index response).

**Errors:**
- `404` if the slug doesn't exist.

## Fields

| Field | Type | Description |
|---|---|---|
| `id` | integer | Surrogate ID. |
| `slug` | string | Stable URL-safe handle. Use for cross-references in other endpoints. |
| `name` | string | Display name. |
| `code` | string | Canonical short code (e.g., `CA`, `ON`, `TOR-ON`). |
| `level` | string | One of `federal`, `provincial`, `territorial`, `municipal`, `regional`, `crown_corp`, `authority`. |
| `region_code` | string \| null | 2-letter province code for sub-provincial jurisdictions (e.g., `ON` for Toronto). |
| `fiscal_year_start_month` | integer | Month (1–12) the jurisdiction's fiscal year begins. Federal/most provincial = 4 (April); most municipal = 1 (January). |
| `default_currency` | string | ISO 4217. All current jurisdictions are `CAD`. |
