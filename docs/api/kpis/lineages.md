# Lineages

Two parallel tables track temporal relationships between entities:

- **Organization lineages** — agency renames, merges, splits, absorptions, spin-offs, revivals.
- **Measure lineages** — same plus methodology revisions, unit changes, scope changes.

Both use the same shape: a row asserts that `predecessor` became `successor` in a specific `transition_year` via a specific `transition_kind`. M-to-1 merges and 1-to-M splits are encoded as multiple rows that share one side.

## Organization lineages

### `GET /api/v1/kpis/organization_lineages`

**Query parameters:**
| Param | Description |
|---|---|
| `predecessor_slug` | Lineage rows where this org is the predecessor. |
| `successor_slug` | Lineage rows where this org is the successor. |
| `jurisdiction_slug` | Lineage rows where either side belongs to this jurisdiction. |
| `transition_year` | One year. |
| `transition_kind` | One of `rename`, `merge`, `split`, `absorb`, `spin_off`, `revived`. |
| `per_page` | Default 50. |

**Example:**
```bash
# All renames/merges in Toronto's org tree
curl 'http://localhost:3000/api/v1/kpis/organization_lineages?jurisdiction_slug=toronto'
```

**Response:**
```json
{
  "data": [
    {
      "id": 1,
      "transition_year": 2024,
      "transition_kind": "split",
      "notes": null,
      "acknowledged_in_document_id": null,
      "predecessor": {
        "id": 56,
        "slug": "shelter-support-and-housing-administration",
        "canonical_name": "Shelter, Support and Housing Administration"
      },
      "successor": {
        "id": 49,
        "slug": "toronto-shelter-and-support-services",
        "canonical_name": "Toronto Shelter and Support Services"
      }
    },
    {
      "id": 2,
      "transition_year": 2024,
      "transition_kind": "split",
      "predecessor": { "slug": "shelter-support-and-housing-administration", "...": "..." },
      "successor": { "slug": "housing-secretariat", "...": "..." }
    }
  ]
}
```

The two rows above encode a 1-to-2 split: SSHA → TSSS + Housing Secretariat. Each successor gets its own row sharing the predecessor.

### Transition kinds

| Kind | Meaning |
|---|---|
| `rename` | Same entity, new name. (Modeled as two org rows + one lineage row to preserve historical citations.) |
| `merge` | Multiple predecessors → one successor. One lineage row per predecessor. |
| `split` | One predecessor → multiple successors. One lineage row per successor. |
| `absorb` | One entity's responsibilities absorbed into another (predecessor ceases to exist; successor continues unchanged). |
| `spin_off` | New entity carved out of an existing one (predecessor continues; successor is new). |
| `revived` | An entity that ceased to exist is brought back. |

## Measure lineages

### `GET /api/v1/kpis/measure_lineages`

Same shape as organization lineages, with one extra `transition_kind`.

**Query parameters:**
| Param | Description |
|---|---|
| `predecessor_id` | Lineage rows where this measure is the predecessor. |
| `successor_id` | Lineage rows where this measure is the successor. |
| `organization_slug` | Lineage rows where either side belongs to a measure under this org. |
| `transition_year` | One year. |
| `transition_kind` | See below. |
| `per_page` | Default 50. |

**Response:**
```json
{
  "data": [
    {
      "id": 1,
      "transition_year": 2023,
      "transition_kind": "methodology_revision",
      "notes": "Scope expanded to include streaming content starting FY24.",
      "acknowledged_in_document_id": 2139,
      "predecessor": { "id": 1234, "slug": "...", "canonical_name": "...", "organization_slug": "canadian-heritage" },
      "successor":   { "id": 2414, "slug": "...", "canonical_name": "...", "organization_slug": "canadian-heritage" }
    }
  ]
}
```

### Transition kinds

| Kind | Meaning |
|---|---|
| `rename` | Same indicator, new name. |
| `methodology_revision` | Definition changed materially; pre/post values aren't directly comparable. |
| `split` | One measure → multiple. |
| `merge` | Multiple measures → one. |
| `unit_change` | Same indicator, new unit (e.g., counts → rate per 100k). |
| `scope_change` | Population or geographic scope changed. |
| `revived` | An indicator reintroduced after being dropped. |

## Why lineages exist

Without lineage tracking, a measure rename or methodology revision creates a "ghost" — pre-2023 values for the old name and post-2023 values for the new name look like two separate time series with a gap. Lineage rows let consumers stitch them back together while making the discontinuity explicit:

```bash
# Get all citations across the lineage chain
curl 'http://localhost:3000/api/v1/kpis/measure_lineages?successor_id=2414'
# → returns predecessor 1234. Now query citations for both.
curl 'http://localhost:3000/api/v1/kpis/citations?measure_id=1234'
curl 'http://localhost:3000/api/v1/kpis/citations?measure_id=2414'
```

Knowing the lineage row's `transition_kind` tells you whether the values can be charted as one continuous series (`rename`) or should be visually delimited (`methodology_revision`, `scope_change`).
