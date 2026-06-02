# KPI Extraction Agent Contract (post-Phase-8)

Extraction agents (the `extract-kpis` skill and successors) write to
`POST /api/v1/kpis/admin/citations` and create extracted_observations.
These rows are **claims**, never facts — they start with `review_status='pending'`
and become canonical only after `POST /api/v1/kpis/admin/extracted_observations/:id/approve`.

## Per-observation payload

```jsonc
{
  // Required: identifies the canonical metric and source.
  "measure_id":       42,
  "document_id":      117,
  "measurement_year": 2024,
  "value_type":       "actual",                 // actual | target | projected | plan | budget
  "period_basis":     "full_year",              // full_year | ytd_q1..q3 | as_of_date

  // Absolute period (preferred over fiscal-year labels in the long run).
  "period_start": "2024-01-01",
  "period_end":   "2024-12-31",
  "period_type":  "calendar_year",

  // Value + the original string the agent saw, plus the agent's unit guess.
  "value_numeric": 83.0,
  "value_text":    null,
  "value_raw":     "83%",
  "unit_raw":      "%",

  // Raw labels (NEVER drop these — reviewers compare to resolved FKs below).
  "metric_name_raw":              "Transit on-time performance",
  "geography_name_raw":           "City of Edmonton",
  "jurisdiction_name_raw":        "City of Edmonton municipal jurisdiction",
  "reporting_organization_raw":   "Edmonton Transit Service",
  "responsible_organization_raw": "Edmonton Transit Service",
  "observed_organization_raw":    "Edmonton Transit Service",

  // Three entity roles (resolved FKs). Spec §4.4:
  // - reporting:   who published the document
  // - responsible: who owns / manages the KPI
  // - observed:    who or what the metric is about
  "reporting_organization_id":   55,
  "responsible_organization_id": 55,
  "observed_organization_id":    55,
  "geo_boundary_id":             910,
  "jurisdiction_id":             4,

  // Source evidence — every claim must be traceable.
  "source_page":    12,
  "source_section": "Performance Measures",
  "source_table":   "Table 3.1",
  "source_chart":   null,
  "evidence_quote": "On-time performance: 83%¹",

  // Composition / component for part-of-whole metrics (Phase 5).
  "composition_id": null,
  "component_id":   null,

  // Per-field confidence + needs-review hint.
  "extraction_confidence": 0.92,
  "needs_review":          true,

  "notes":         null,
  "agent_run_id":  3007
}
```

## Follow-up: footnotes (Phase 3)

When the document has footnotes:

```
POST /api/v1/kpis/admin/documents/:document_id/footnotes
{ "footnote_text": "On-time = no more than five minutes late.",
  "page": 12, "marker": "1", "agent_run_id": 3007 }
```

Then link:

```
POST /api/v1/kpis/admin/extracted_observations/:id/footnote_links
{ "source_footnote_id": 88 }
```

## Follow-up: agent assertions (Phase 3)

For per-field reasoning the reviewer should be able to audit:

```
POST /api/v1/kpis/admin/extracted_observations/:id/assertions
{ "assertion_type": "unit",
  "assertion_text": "value is in thousands of dollars",
  "confidence":     0.9,
  "evidence_quote": "Table notes: amounts shown in $000s.",
  "source_page":    12 }
```

## Review flags (Phase 2)

Whenever the agent is uncertain in a way that needs human attention, write
a typed flag rather than guessing:

```
POST /api/v1/kpis/admin/extracted_observations/:id/review_flags
{ "flag_type": "geo_entity_confusion",
  "severity":  "medium",                  // low | medium | high | critical
  "message":   "Edmonton ambiguous: CSD vs CMA vs municipal government",
  "evidence":  "Section names refer to 'Edmonton region' without further qualification." }
```

Flag types (from spec §7.4): `low_confidence_extraction`, `missing_footnote`,
`unit_ambiguous`, `period_ambiguous`, `metric_definition_changed`,
`large_year_over_year_change`, `value_conflicts_with_prior_source`,
`geography_ambiguous`, `entity_ambiguous`, `jurisdiction_ambiguous`,
`negative_value_unexpected`, `source_table_unclear`,
`possible_total_vs_per_capita_confusion`, `possible_budget_vs_actual_confusion`,
`entity_scope_ambiguous`, `geo_entity_confusion`, `geo_version_missing`,
`components_do_not_sum_to_total`, `components_do_not_sum_to_100`,
`new_component_detected`, `component_split_or_merge_possible`,
`crosswalk_missing`, `metric_not_aggregable`, `wrong_weight_basis`,
`partial_coverage`, `low_crosswalk_confidence`, `crosswalk_version_mismatch`,
`ratio_requires_recomputation`.

## What the agent must NOT do

- **Never** write directly to `canonical_observations` — there's no admin
  endpoint for that. The only path is `extracted → reviewed → approved`.
- **Never** allocate a crosswalked value silently. Use
  `Warehouse::GeographyCrosswalkSet::Allocator` — it refuses to crosswalk
  rates/ratios/medians/indexes unless an explicit
  `crosswalk_metric_compatibility` row says otherwise (Phase 6 guard).
- **Never** invent new measures inline. If a raw metric name doesn't
  resolve through `Warehouse::Measure::Resolver` (alias → canonical_name →
  slug), create a `review_flag` with `metric_name_raw` set and let a
  reviewer either map it to an existing measure or create a new one.
- **Never** drop the raw text. Every `*_raw` column is the original
  string the reviewer compares against — losing it makes audits impossible.

## Public read endpoints (post-Phase-8)

- `GET /api/v1/kpis/observations` → canonical_observations only, with all
  spec §14 filters (measure_id, measure_category, composition_id,
  component_id, observed_organization_slug, reporting_organization_slug,
  jurisdiction_slug, geo_boundary_id, year, value_type, period_basis,
  status, is_total).
- `GET /api/v1/kpis/observations/:id` → one canonical fact + derivation_count.
- `GET /api/v1/kpis/observations/:id/derivations` → derived observations
  for that fact (crosswalked / aggregated), with `derivation_method`
  always labelled. Derived values never appear in the canonical list.
- `GET /api/v1/kpis/facts` → backwards-compatible read of `measure_facts`
  (latest canonical observation per measure/year/value_type/period_basis).
- `GET /api/v1/kpis/citations` → extracted_observations (claims). Pass
  `?review_status=approved` to filter; by default returns all states for
  agent-run debugging.
