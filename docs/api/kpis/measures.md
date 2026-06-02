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
- `GET /api/v1/kpis/measures/:id/compositions` — composition/component catalog for one measure.

## Compositions

Use compositions when a measure has structured parts, such as debt by currency,
revenue by source, or service volume by channel.

### `GET /api/v1/kpis/compositions`

Lists compositions and their components. This endpoint is intended for ingestion
agents that need to discover existing `composition_id` and `component_id` values
before posting extracted observations.

**Query parameters:**
| Param | Description |
|---|---|
| `organization_slug` | Restrict to measures owned by one organization. |
| `jurisdiction_slug` | Restrict to organizations in one jurisdiction. |
| `measure_id` | Restrict to one measure. |
| `composition_type` | Restrict to one composition type, e.g. `by_currency`. |
| `per_page` | Default 100. |
| `page` | Default 1. |

**Example:**
```bash
curl 'http://localhost:3000/api/v1/kpis/compositions?organization_slug=edmonton'
curl 'http://localhost:3000/api/v1/kpis/measures/2414/compositions'
```

**Response:**
```json
{
  "data": [
    {
      "id": 12,
      "measure": {
        "id": 2414,
        "slug": "total-debt",
        "canonical_name": "Total debt",
        "organization": { "id": 55, "slug": "edmonton", "canonical_name": "City of Edmonton" }
      },
      "composition_type": "by_currency",
      "name": "Debt by currency",
      "expected_total": 100,
      "expected_total_unit": { "id": 3, "symbol": "%" },
      "allow_other": true,
      "allow_unknown": true,
      "notes": null,
      "components": [
        {
          "id": 44,
          "measure_id": 2414,
          "composition_id": 12,
          "component_type": "currency",
          "component_code": "CAD",
          "component_name": "Canadian dollar",
          "parent_component_id": null,
          "valid_from": null,
          "valid_to": null,
          "sort_order": 1,
          "notes": null
        }
      ]
    }
  ],
  "meta": { "page": 1, "pages": 1, "count": 1, "per_page": 100 }
}
```

## Fields

| Field | Type | Description |
|---|---|---|
| `id` | integer | Surrogate ID. |
| `slug` | string | Parameterized from canonical_name. Unique per (organization, slug). |
| `canonical_name` | string | The measure name as published. |
| `organization` | object \| null | NULL for cross-agency measures. |
| `unit` | object | Unit metadata. `value_numeric` on citations/facts is in **display** units (the unit's natural notation); `scale` and `base_unit` give the conversion to base for cross-unit math. See "Unit math" below. |
| `service_category` | string \| null | Free-text grouping from the source doc — Core Responsibility (federal), service area (provincial/municipal), etc. |
| `first_seen_year` / `last_seen_year` | integer \| null | Range hint of where this measure has citations. |
| `description` | string \| null | (Show only.) Long-form definition from the source. |

## Unit math

**Convention: `value_numeric` is stored in DISPLAY units — the unit's own natural notation.** `unit.scale` is the multiplier you apply when downstream code needs the value in `base_unit` form for cross-unit math.

| Unit symbol | scale | base_unit | Example `value_numeric` | What it means |
|---|---|---|---|---|
| `$B` | `1e9` | `dollars` | `65.3` | $65.3 billion (display) → `65.3 * 1e9` = $65,300,000,000 in dollars |
| `$M` | `1e6` | `dollars` | `450` | $450 million |
| `$` | `1.0` | `dollars` | `1234.56` | $1,234.56 |
| `%` | `0.01` | `ratio` | `90` | 90 percent (display) → `90 * 0.01` = `0.9` as a ratio |
| `count_thousands` | `1000` | `count` | `2047` | 2,047 thousand items → 2,047,000 |
| `count` | `1.0` | `count` | `1923000` | 1,923,000 items |

You can render the value directly with the unit symbol (`65.3 $B`, `90%`, `2047 count_thousands`) without normalizing. If you do need to compare across units (e.g., sum a `$M` and a `$B`), multiply each by its `unit.scale` first.

For `kind: "rate"` units (e.g., `$/sqft`, `count per 100km`), also apply `denominator_unit` + `denominator_scale` to normalize the denominator.
