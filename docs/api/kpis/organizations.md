# Organizations

A government organization — federal department, provincial agency, municipal department, crown corporation, etc. Organizations are scoped to a jurisdiction and can have a parent (e.g., a division under a department).

Historical predecessors are first-class rows. When an agency is renamed or split, the old slug persists as its own organization row with `active_to_year` set; the new entity gets its own row and an `organization_lineage` row links them.

## `GET /api/v1/kpis/jurisdictions/:jurisdiction_slug/organizations`

List organizations within a jurisdiction.

**Path parameters:**
- `jurisdiction_slug` — e.g., `ca`, `toronto`.

**Response:**
```json
{
  "data": [
    {
      "id": 60,
      "slug": "canadian-heritage",
      "canonical_name": "Canadian Heritage",
      "kind": "department",
      "active_from_year": null,
      "active_to_year": null,
      "description": "Department of Canadian Heritage (PCH)…",
      "jurisdiction_id": 1
    }
  ]
}
```

## `GET /api/v1/kpis/jurisdictions/:jurisdiction_slug/organizations/:slug`

Show one organization with its lineage relationships.

**Response:**
```json
{
  "id": 60,
  "slug": "canadian-heritage",
  "canonical_name": "Canadian Heritage",
  "kind": "department",
  "active_from_year": null,
  "active_to_year": null,
  "description": "…",
  "jurisdiction_id": 1,
  "lineages": {
    "predecessors": [
      {
        "other_organization": { "id": 99, "slug": "department-of-communications", "canonical_name": "Department of Communications" },
        "transition_year": 1996,
        "transition_kind": "rename",
        "acknowledged_in_document_id": null,
        "notes": null
      }
    ],
    "successors": []
  }
}
```

The `lineages.predecessors` array lists rows where this org is the *successor*; `lineages.successors` lists rows where this org is the *predecessor*. (M-to-1 merges and 1-to-M splits are encoded as multiple rows sharing one side.)

## Fields

| Field | Type | Description |
|---|---|---|
| `id` | integer | Surrogate ID. |
| `slug` | string | Stable URL-safe handle, unique per jurisdiction. |
| `canonical_name` | string | Authoritative business name (typically the form used on canada.ca or the agency's own site). |
| `kind` | string \| null | Free-text classifier — `department`, `agency`, `crown_corp`, `office`, `division`, `board`. |
| `active_from_year` | integer \| null | First year this entity existed (NULL if it predates the dataset). |
| `active_to_year` | integer \| null | Last year this entity existed (NULL if still active). |
| `description` | string \| null | Short prose summary. |
| `jurisdiction_id` | integer | FK to the jurisdiction. |

## Filtering

The index endpoint is intentionally simple (one list per jurisdiction). To search across jurisdictions or by name fragment, use a small client-side filter on the list — there are only ~100 orgs federally and ~60 in Toronto today. If you need server-side filtering, file an issue.
