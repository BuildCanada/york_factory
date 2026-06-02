---
name: ingest-government-kpis
description: Extract government performance measures, KPIs, service indicators, targets, actuals, and budget-plan values from Canadian federal, provincial, municipal, or agency source documents and write them to the York Factory KPI admin API as reviewed claims. Use when an agent needs to populate, backfill, or update warehouse KPI data from PDFs, HTML reports, departmental plans, departmental results reports, annual reports, budgets, service plans, or operating notes.
---

# Ingest Government KPIs

Extract KPI tables from one source document and write them to York Factory through the KPI admin API. Agent output is a claim, not a fact: `/admin/citations` creates `warehouse.extracted_observations`, and a reviewer later approves them into `canonical_observations`.

One invocation should handle one source document. Use one `agent_run` per source document.

## Hard Rules

- Use the batch body exactly: `{ "agent_run_id": ID, "citations": [ ... ] }`.
- Do not POST a bare single observation to `/admin/citations`.
- Exit without writing if the supplied URL is an index/listing page instead of a single report document URL.
- Use current field names: `source_page` and `value_raw`.
- Do not use legacy field names: `page_number` or `value_raw_text`.
- Preserve raw source text in `value_raw`, `metric_name_raw`, `geography_name_raw`, `jurisdiction_name_raw`, and organization `*_raw` fields.
- Do not write to `canonical_observations`; approval is a separate reviewer action.
- Do not invent units. If `unit_symbol` is unknown, stop and report the unit that must be added to `db/seeds/kpis/units.yml`.
- If extraction is uncertain, set `needs_review: true` and add a typed review flag after the citation is created.

## Preflight

Set these shell variables before API calls:

```bash
API="${YORK_FACTORY_API_URL:-http://localhost:3000}"
TOKEN="${YORK_FACTORY_KPI_TOKEN:-$(cat ~/.config/york-factory/kpi-token 2>/dev/null)}"
test -n "$TOKEN" || { echo "Missing YORK_FACTORY_KPI_TOKEN"; exit 1; }
curl -sf "$API/up" >/dev/null || { echo "Start the Rails server: bin/rails server"; exit 1; }
```

Every write request needs:

```bash
-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

## Workflow

### 1. Resolve Jurisdiction

```bash
curl -s "$API/api/v1/kpis/jurisdictions" \
  | jq '.data[] | {id, slug, name, level, fiscal_year_start_month}'
```

Pick the existing jurisdiction slug. If it does not exist, stop and report that reference data must be seeded.

### 2. Resolve Or Create Organization

List organizations under the jurisdiction:

```bash
curl -s "$API/api/v1/kpis/jurisdictions/$JURISDICTION_SLUG/organizations" \
  | jq '.data[] | {id, slug, canonical_name, active_from_year, active_to_year}'
```

If the source clearly identifies a new organization, create it:

```bash
curl -s -X POST "$API/api/v1/kpis/admin/organizations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg jur "$JURISDICTION_SLUG" \
    --arg slug "$ORG_SLUG" \
    --arg name "$CANONICAL_NAME" \
    --arg kind "$ORG_KIND" \
    --argjson aliases "${ALIASES_JSON:-[]}" \
    '{organization:{
      jurisdiction_slug:$jur,
      slug:$slug,
      canonical_name:$name,
      kind:$kind,
      aliases:$aliases
    }}')"
```

If the source says the organization replaced, absorbed, split from, or renamed another organization, mention that in the final report and create lineage only when the predecessor/successor IDs are clear.

### 3. Open Agent Run

```bash
RUN=$(curl -s -X POST "$API/api/v1/kpis/admin/agent_runs" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg jur "$JURISDICTION_SLUG" \
    --arg org "$ORG_SLUG" \
    --arg url "$DOC_URL" \
    --argjson fiscal_year "$FISCAL_YEAR" \
    --arg version "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
    '{agent_run:{
      agent_name:"ingest-government-kpis",
      agent_version:$version,
      input_params:{
        jurisdiction_slug:$jur,
        organization_slug:$org,
        fiscal_year:$fiscal_year,
        doc_url:$url
      }
    }}')")
RUN_ID=$(echo "$RUN" | jq -r '.id')
test "$RUN_ID" != "null" || { echo "$RUN"; exit 1; }
```

### 4. Register Source Document

Use the canonical public URL as `doc_url`. For HTML, use the page URL. For PDFs, use the PDF URL.

Before registering, inspect the page title and links. If the page is a listing
or index of multiple reports, stop with a clear message and ask the caller to
use `orchestrate-government-kpi-series` on the listing URL. Do not choose one
linked report in this skill.

```bash
DOC=$(curl -s -X POST "$API/api/v1/kpis/admin/documents" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg jur "$JURISDICTION_SLUG" \
    --arg org "$ORG_SLUG" \
    --arg url "$DOC_URL" \
    --arg source_page_url "${SOURCE_PAGE_URL:-}" \
    --arg title "$DOC_TITLE" \
    --arg type "$DOC_TYPE" \
    --argjson fiscal_year "$FISCAL_YEAR" \
    --argjson run_id "$RUN_ID" \
    '{document:{
      jurisdiction_slug:$jur,
      organization_slug:$org,
      fiscal_year:$fiscal_year,
      doc_url:$url,
      source_page_url:(if $source_page_url == "" then null else $source_page_url end),
      doc_title:$title,
      doc_type:$type,
      agent_run_id:$run_id
    }}')")
DOC_ID=$(echo "$DOC" | jq -r '.id')
test "$DOC_ID" != "null" || { echo "$DOC"; exit 1; }
```

### 5. Extract Measures And Values

Read only relevant pages or sections first. Search headings like:

- "Performance Measures"
- "Departmental result indicator"
- "Service Performance"
- "Key Service Levels"
- "Outcomes and Performance Measures"
- "Targets and Actuals"

For each measure, capture:

- `canonical_name`: stable measure name.
- `slug`: lowercase ASCII, non-alphanumeric runs replaced with `-`.
- `unit_symbol`: existing `warehouse.units.symbol`.
- `service_category`: source section or core responsibility.
- `aggregation_type` if confidently known is useful context, but the current create endpoint may not accept it. Record it in notes/report if not accepted.

Value conventions:

- `value_numeric` is in the measure's display unit. For `$B`, send `5.3`; for `%`, send `83`; for `CAD`, send full dollars.
- `value_text` is for qualitative/date/pass-fail values.
- `value_raw` is the exact visible source cell.
- `source_page` is the physical PDF page index used by the reader, 1-based. For HTML, leave it null and use `source_section`.
- `measurement_year` is the year the value is about. For federal `2024-25`, use `2025`.
- `value_type` must be one of `actual`, `target`, `projected`, `plan`, `budget`.
- `period_basis` defaults to `full_year`; use `ytd_q1`, `ytd_q2`, `ytd_q3`, or `as_of_date` only when the source clearly says so.
- Prefer `period_start`, `period_end`, and `period_type` when the source period is clear.

Before creating measures, query the existing catalog for the organization:

```bash
curl -s "$API/api/v1/kpis/measures?organization_slug=$ORG_SLUG&per_page=100" \
  | jq '.data[] | {id, slug, canonical_name, unit: .unit.symbol, service_category}'
```

If a source row looks like a structured part of a measure, query existing
compositions and components:

```bash
curl -s "$API/api/v1/kpis/compositions?organization_slug=$ORG_SLUG&per_page=100" \
  | jq '.data[] | {measure_id: .measure.id, composition_id: .id, composition_type, name,
                   components: [.components[] | {id, component_type, component_code, component_name}]}'
```

For one known measure:

```bash
curl -s "$API/api/v1/kpis/measures/$MEASURE_ID/compositions" \
  | jq '.data[] | {composition_id: .id, composition_type, components: .components}'
```

Use existing `composition_id` and `component_id` only when the source component
matches clearly. If a new component or composition appears, leave those IDs null,
set `needs_review: true`, and add a `new_component_detected` or
`component_split_or_merge_possible` review flag after creating the observation.

### 6. Upsert Measures

Create one measure for each distinct metric definition.

```bash
M=$(curl -s -X POST "$API/api/v1/kpis/admin/measures" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg org "$ORG_SLUG" \
    --arg slug "$MEASURE_SLUG" \
    --arg name "$CANONICAL_NAME" \
    --arg unit "$UNIT_SYMBOL" \
    --arg category "$SERVICE_CATEGORY" \
    --argjson fiscal_year "$FISCAL_YEAR" \
    --argjson run_id "$RUN_ID" \
    '{measure:{
      organization_slug:$org,
      slug:$slug,
      canonical_name:$name,
      unit_symbol:$unit,
      service_category:$category,
      last_seen_year:$fiscal_year,
      agent_run_id:$run_id
    }}')")
MEASURE_ID=$(echo "$M" | jq -r '.id')
```

If `MEASURE_ID` is null and the response says `unknown_unit`, stop and report the missing `unit_symbol`.

Create a new measure instead of reusing an existing one when the source definition changes materially. Mention likely lineages in the final report.

### 7. Post Extracted Observations

Build a JSON array and POST once per document. This is the exact citation row shape:

```json
{
  "measure_id": 5678,
  "document_id": 1234,
  "measurement_year": 2025,
  "value_type": "actual",
  "period_basis": "full_year",
  "period_start": "2024-04-01",
  "period_end": "2025-03-31",
  "period_type": "fiscal_year",
  "value_numeric": 83.0,
  "value_text": null,
  "value_raw": "83%",
  "unit_raw": "%",
  "composition_id": null,
  "component_id": null,
  "metric_name_raw": "Transit on-time performance",
  "geography_name_raw": "City of Edmonton",
  "jurisdiction_name_raw": "City of Edmonton",
  "reporting_organization_raw": "City of Edmonton",
  "responsible_organization_raw": "Edmonton Transit Service",
  "observed_organization_raw": "Edmonton Transit Service",
  "reporting_organization_id": 55,
  "responsible_organization_id": 55,
  "observed_organization_id": 55,
  "geo_boundary_id": null,
  "jurisdiction_id": 4,
  "source_page": 12,
  "source_section": "Performance Measures",
  "source_table": "Table 3.1",
  "source_chart": null,
  "evidence_quote": "On-time performance: 83%",
  "extraction_confidence": 0.92,
  "needs_review": false,
  "notes": null
}
```

Batch POST:

```bash
curl -s -X POST "$API/api/v1/kpis/admin/citations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --argjson run_id "$RUN_ID" \
    --argjson rows "$CITATIONS_JSON" \
    '{agent_run_id:$run_id, citations:$rows}')"
```

Check the response:

- `inserted` is the number of new claims.
- `skipped_duplicate` is expected on reruns.
- `ids` are extracted observation IDs for follow-up flags, assertions, and footnotes.

If the API returns `unsupported_citation_fields`, replace the reported fields. The known replacements are `page_number -> source_page` and `value_raw_text -> value_raw`.

### 8. Add Review Context When Needed

Use review flags for uncertainty that a reviewer must inspect:

```bash
curl -s -X POST "$API/api/v1/kpis/admin/extracted_observations/$OBS_ID/review_flags" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"flag_type":"unit_ambiguous","severity":"high","message":"Table header could mean millions or billions","evidence":"Header says $000s but footnote says $ millions."}'
```

Common flag types:

- `low_confidence_extraction`
- `missing_footnote`
- `unit_ambiguous`
- `period_ambiguous`
- `metric_definition_changed`
- `geography_ambiguous`
- `entity_ambiguous`
- `jurisdiction_ambiguous`
- `possible_total_vs_per_capita_confusion`
- `possible_budget_vs_actual_confusion`
- `source_table_unclear`

Use assertions for field-level reasoning:

```bash
curl -s -X POST "$API/api/v1/kpis/admin/extracted_observations/$OBS_ID/assertions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"assertion_type":"unit","assertion_text":"Value is shown in percent, not ratio.","confidence":0.95,"evidence_quote":"Target: 90%","source_page":12}'
```

Use footnotes when source footnotes materially affect interpretation:

```bash
FN=$(curl -s -X POST "$API/api/v1/kpis/admin/documents/$DOC_ID/footnotes" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"footnote_text":"Includes only weekday service.","page":12,"marker":"1"}')
FN_ID=$(echo "$FN" | jq -r '.id')

curl -s -X POST "$API/api/v1/kpis/admin/extracted_observations/$OBS_ID/footnote_links" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --argjson id "$FN_ID" '{source_footnote_id:$id}')"
```

### 9. Close The Run

Always close the run. On success:

```bash
curl -s -X PATCH "$API/api/v1/kpis/admin/agent_runs/$RUN_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg report "$REPORT_MD" \
    --argjson summary "$SUMMARY_JSON" \
    '{agent_run:{status:"completed", report:$report, summary:$summary}}')"
```

On unrecoverable failure:

```bash
curl -s -X PATCH "$API/api/v1/kpis/admin/agent_runs/$RUN_ID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg msg "$ERROR_MESSAGE" \
    '{agent_run:{status:"failed", error_message:$msg}}')"
```

The final report should include:

- source URL and document title
- `agent_run_id`
- counts for documents, measures, citations inserted, citations skipped, flags, assertions, and footnotes
- unknown units or unresolved reference data
- methodology changes or lineage candidates
- cells skipped because they were unreadable or ambiguous
