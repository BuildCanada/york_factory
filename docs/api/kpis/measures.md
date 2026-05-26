# Measures

A measure is a single performance indicator definition. Its values across years live in citations (raw) and facts (resolved). A measure has exactly one unit and belongs to one organization (or none, for cross-agency indicators).

## `GET /api/v1/kpis/measures`

List measures, paginated.

**Query parameters:**
| Param | Description |
|---|---|
| `jurisdiction_slug` | Restrict to one jurisdiction. |
| `organization_slug` | Restrict to one org (overrides `jurisdiction_slug` if both given). |
| `per_page` | Default 50. |
| `page` | Default 1. |

**Example:**
```bash
curl 'http://localhost:3000/api/v1/kpis/measures?jurisdiction_slug=ca&per_page=20'
```

**Response:**
```json
{
  "data": [
    {
      "id": 2414,
      "slug": "gross-domestic-product-gdp-of-the-canadian-cultural-sector",
      "canonical_name": "Gross domestic product (GDP) of the Canadian cultural sector",
      "organization": {
        "id": 60,
        "slug": "canadian-heritage",
        "canonical_name": "Canadian Heritage",
        "active_from_year": null,
        "active_to_year": null
      },
      "unit": {
        "id": 14,
        "symbol": "$B",
        "kind": "absolute",
        "base_unit": "dollars",
        "scale": 1000000000.0,
        "currency_code": "CAD",
        "denominator_unit": null,
        "denominator_scale": null
      },
      "service_category": "Creative industries are successful in the digital economy…",
      "first_seen_year": null,
      "last_seen_year": 2025
    }
  ],
  "meta": { "page": 1, "pages": 25, "count": 1234, "per_page": 50 }
}
```

## `GET /api/v1/kpis/measures/:id`

Show one measure with description, lineages, and full unit detail.

**Response (additions over the index):**
```json
{
  "description": "Long-form description from the source document…",
  "lineages": {
    "predecessors": [
      {
        "predecessor_id": 1234,
        "successor_id": 2414,
        "transition_year": 2023,
        "transition_kind": "methodology_revision",
        "notes": "Scope expanded to include streaming starting 2024."
      }
    ],
    "successors": []
  }
}
```

## Nested sub-resources

- `GET /api/v1/kpis/measures/:id/facts` — resolved canonical values. See [facts.md](./facts.md).
- `GET /api/v1/kpis/measures/:id/citations` — raw observations from each source. See [citations.md](./citations.md).

## Fields

| Field | Type | Description |
|---|---|---|
| `id` | integer | Surrogate ID. |
| `slug` | string | Parameterized from canonical_name. Unique per (organization, slug). |
| `canonical_name` | string | The measure name as published. |
| `organization` | object \| null | NULL for cross-agency measures. |
| `unit` | object | Unit metadata — `symbol` is what's typically displayed; `scale` and `base_unit` give the SI-style normalization for math (e.g., `$B` has `scale=1e9` `base_unit=dollars`). |
| `service_category` | string \| null | Free-text grouping from the source doc — Core Responsibility (federal), service area (provincial/municipal), etc. |
| `first_seen_year` / `last_seen_year` | integer \| null | Range hint of where this measure has citations. |
| `description` | string \| null | (Show only.) Long-form definition from the source. |

## Unit math

To convert `value_numeric` into its `base_unit` form, multiply by `unit.scale`. For example, a measure with `unit.symbol = "$B"` and a citation `value_numeric: 65.3` represents $65.3 billion — i.e., `65.3 * 1_000_000_000 = $65,300,000,000` in base dollars. Most consumers should just display the number with the unit symbol; the normalization exists for cross-unit math (e.g., comparing `$M` and `$B` values).

For `kind: "rate"` units (e.g., `$/sqft`), also use `denominator_unit` + `denominator_scale`.
