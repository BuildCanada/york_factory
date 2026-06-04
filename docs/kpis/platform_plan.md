# Government Metrics Platform — Implementation Plan

Phased plan to evolve the current York Factory `warehouse.*` KPI schema into the full government-metrics data platform spec (claim → review → canonical → derived, with first-class geography, composite metrics, crosswalks, and alerts).

Nothing is in production yet, so renames and structural changes are fair game. All current `measure_citations` rows become pending-review `extracted_observations` after Phase 1.

---

## Cross-cutting design decisions

These apply across phases; recording them up front so individual phase migrations stay consistent.

### Three entity roles on every observation

Every `extracted_observations` and `canonical_observations` row carries:

- `reporting_organization_id` — who published the document.
- `responsible_organization_id` — who owns / manages the KPI.
- `observed_organization_id` — who or what the metric is about.

Plus explicit `geo_boundary_id` and `jurisdiction_id`, with `*_raw` text columns mirroring each resolved FK so the agent's raw extraction is always preserved.

### Measures stay org-scoped; `metric_aliases` bridges across jurisdictions

Keep `measures.organization_id`. The current schema already supports both modes:

- **Org-specific measures** (`organization_id` set, unique on `[organization_id, slug]`): Edmonton's `total_debt`, Calgary's `total_debt`, each defined per the publishing org's methodology.
- **Canonical measures** (`organization_id IS NULL`, globally unique slug): jurisdiction-agnostic concepts like StatsCan's `total_debt` or a Build-Canada-defined reference metric.

`metric_aliases` (added in Phase 4) is the bridge for cross-jurisdiction comparison. When Edmonton's and Calgary's `total_debt` are truly equivalent in definition, both get an alias row pointing to the same canonical measure. A "compare across municipalities" dashboard groups by canonical; a single-jurisdiction view uses the org's own measure directly.

`metric_aliases` also keeps its original spec role: mapping raw extracted text ("Tax-supported debt", "Net tax supported debt") to the right measure so the agent doesn't re-resolve the same string on every run.

### Definition differences — the honest approach

When two jurisdictions report metrics that *look* similar but are defined differently (e.g. Edmonton's `tax_supported_debt` vs Calgary's `net_debt`):

- Keep them as **separate measures**.
- Link via `metric_aliases` *only* when they're truly equivalent per documented methodology.
- Otherwise, the dashboard surfaces both with a "definitions differ — not directly comparable" footnote.
- No automatic cross-definition normalization. No `derivation_method='definition_normalization'` shortcut. If a Government-of-Canada-style standard mapping ever lands, revisit then.

`metric_versions` still tracks definition drift *within* one measure over time (e.g. a province changes how it computes net debt in 2024). `metric_lineages` still tracks rename/merge/split *between* measures.

### Reported aggregates vs derived aggregates

Never conflate the two:

| Case | Lives in |
|------|----------|
| Government publishes a rolled-up number ("Total Alberta municipal debt = $X") | `canonical_observations`, `is_total=true`, `observed_entity` = synthetic "All Alberta municipalities" or null with `geography=Alberta` |
| Dashboard sums constituent observations itself | `derived_observations`, `derivation_method='aggregation'`, with constituent observation IDs |

When a reported aggregate disagrees with the sum of components, that's a `composition_validation_result` finding, not a silent reconciliation.

### Period alignment across jurisdictions

`canonical_observations.period_start` / `period_end` are absolute dates, never fiscal-year labels. Jurisdictions have `fiscal_year_start_month` already; a display-time helper resolves "FY2024" against the jurisdiction's calendar so federal FY (Apr–Mar) and municipal FY (Jan–Dec) line up correctly in dashboards.

---

## Phase 1 — Claim/canonical split + entity roles (foundation)

**Goal:** Stop treating agent output as truth. Establish `extracted → canonical` promotion.

- Rename `warehouse.measure_citations` → `warehouse.extracted_observations`.
- Add to `extracted_observations`:
  - Three entity roles: `reporting_organization_id`, `responsible_organization_id`, `observed_organization_id` (each with a `*_raw` text column).
  - Explicit geo/jurisdiction columns: `geo_boundary_id`, `jurisdiction_id` (today implicit via `measure → organization → jurisdiction` — promote them so an observation can disagree with org defaults).
  - Raw text columns: `metric_name_raw`, `geography_name_raw`, `jurisdiction_name_raw`, `period_label_raw`, `unit_raw`.
  - Evidence: `source_section`, `source_table`, `source_chart`, `evidence_quote`.
  - Review state: `extraction_confidence` numeric 0–1, `needs_review` boolean, `review_status` enum (`pending|approved|rejected|superseded`, default `pending`).
- Create `warehouse.canonical_observations` — approved facts only. Mirrors extracted columns plus `metric_version_id`, `vintage_date`, `status` (reported/estimated/revised/final), `is_total`, `is_residual`, `approved_by`, `approved_at`, FK back to `extracted_observation_id`.
- Replace `measure_facts` view to read from `canonical_observations`. Keep the lateral-window "latest vintage" trick.
- Backfill: every existing row → `review_status='pending'`, `needs_review=true`. Phase 2 queue lights up immediately.
- Public read endpoints (`/api/v1/kpis/*`) switch to canonical_observations; until approvals happen, responses are empty. Acceptable.

## Phase 2 — Review workflow

**Goal:** Make claim → fact promotion a real, auditable process.

- `warehouse.observation_review_flags` (flag_type, severity, message, evidence, resolved_at/by, resolution_notes).
- `warehouse.review_decisions` (reviewer, decision enum, `previous_value` jsonb, `new_value` jsonb, notes).
- `human_review_queue` view — left-join extracted_observations + flags, grouped by observation with max severity + flag count.
- Admin UI (extends existing `admin/agent_runs`): list pending observations side-by-side with source evidence + footnotes; actions: approve, reject, edit value, map to existing metric, create new metric, map geography, map entity, mark as new version, resolve flag.
- Promotion job: on approval, atomically copy extracted → `canonical_observations`.

## Phase 3 — Footnotes + agent assertions

**Goal:** PDF nuance becomes first-class data.

- `warehouse.source_footnotes` (kpi_document_id, page, marker, footnote_text).
- `warehouse.observation_footnotes` join table.
- `warehouse.extraction_assertions` (assertion_type, assertion_text, confidence, evidence_quote, source_page) — captures reasoning like "value is in thousands" or "actuals, not budget" so reviewers can audit.
- Update the `extract-kpis` skill agent contract to emit footnotes + assertions per spec §13.

## Phase 4 — Metric metadata + versions + aliases

**Goal:** Stop re-resolving the same alias on every run. Enable safe crosswalking and cross-jurisdiction comparison.

- Keep `measures.organization_id` (already nullable; NULL means cross-agency canonical).
- Add to `warehouse.measures`: `aggregation_type` enum (additive/semi_additive/average/ratio/median/index/rate/part_of_whole/non_aggregable/unknown), `numerator_measure_id`, `denominator_measure_id`, `higher_is_bad`, `frequency`, `category`.
- Backfill `aggregation_type` with sensible defaults; flag `unknown` rows for review.
- `warehouse.metric_versions` (measure_id, version_label, definition, methodology, active_from/to, source_id, breaking_change). Complements `measure_lineages`: lineages = rename/merge/split *between* measures; versions = definition drift *within* one measure.
- `warehouse.metric_aliases` — dual-purpose:
  - **Raw-text mapping:** `(alias text, measure_id, source_id, valid_from/to)` so the agent resolves "Tax-supported debt" → the right measure deterministically. Wire `EntityResolver` to consult aliases *before* LLM fuzzy match.
  - **Cross-jurisdiction equivalence:** when an org-scoped measure is definitionally equivalent to a canonical measure (`organization_id IS NULL`), add an alias row from the org-scoped measure's canonical_name to the canonical measure. Dashboards use this to group across jurisdictions. If definitions differ, **no alias** — measures stay separate with a "definitions differ" footnote.

## Phase 5 — Composite metrics

**Goal:** Currency exposure, revenue-by-source, debt-by-maturity become structured slices of one measure, not separate hardcoded measures.

- `warehouse.metric_compositions` (measure_id, composition_type, name, expected_total, expected_total_unit_id, allow_other, allow_unknown).
- `warehouse.metric_components` (measure_id, composition_id, component_type, component_code, component_name, parent_component_id, valid_from/to, sort_order).
- `warehouse.metric_component_relationships` (renamed_to / split_into / merged_into / reclassified_as).
- `warehouse.composition_validation_results` (validation_type, status, expected/actual, severity, message).
- Add `composition_id`, `component_id` columns to `extracted_observations` and `canonical_observations`.
- Solid Queue job: recompute composition validation on `canonical_observations` insert — sum-to-total, sum-to-100, missing-component flags.

## Phase 6 — Geography versioning + crosswalks v2 + derived observations

**Goal:** Existing crosswalk tables become spec-compliant; derived values are never confused with reported values.

- Promote `geo_boundaries` to versioned geographies: keep `census_year`, add `valid_from`/`valid_to`, ensure `code_system` is explicit (`statcan_sgc_2021` vs `statcan_sgc_2016`).
- Split current `geo_crosswalks` into:
  - `warehouse.geography_crosswalk_sets` (method, weight_basis, expected_weight_sum, allow_partial_coverage, valid_from/to, source_id).
  - `warehouse.geography_crosswalk_entries` (set_id, from/to, weight, confidence, relationship_type).
- `warehouse.crosswalk_metric_compatibility` (set_id, measure_id, compatibility, reason). This is where the "don't crosswalk a rate directly" guard lives — depends on Phase 4's `aggregation_type`.
- `warehouse.derived_observations` (from_observation_id, crosswalk_set_id, original_geo_id, derived_geo_id, derivation_method, confidence). **Never** writes to `canonical_observations`.
- `crosswalk_weight_checks` view for QA.

## Phase 7 — Alerts

**Goal:** Slow-moving metric monitoring without standing up Prometheus.

- `warehouse.alerts` (measure_id, geo_id, jurisdiction_id, observed_organization_id, condition_type, threshold_value, comparison_period, severity, enabled).
- Scheduled Solid Queue job evaluates conditions (`above`, `below`, `percent_change`, `missing_update`, `rank_change`, `new_definition`, `new_component`, `conflicting_source`) against `canonical_observations`.
- Reuse existing SES mailer config for notifications.

## Phase 8 — Agent contract + dashboard views

**Goal:** Make the upstream agent emit spec-shaped JSON and expose canonical data publicly.

- Rewrite `extract-kpis` skill output to per-observation contract in spec §13.1: 3 entity roles, raw + resolved geo/jurisdiction/period, evidence_quote, footnotes array, per-field confidence, review_flags array.
- Public API v1:
  - `/kpis` → `canonical_observations` only, filtered by metric/category/composition/component/geo/jurisdiction/entity-role/period/source.
  - `/kpis/:id/derivations` → `derived_observations` for that fact with `derivation_method` labelled.
  - `/kpis/:id/lineage` → version + lineage chain.
- Admin dashboards per spec §14: Edmonton debt, Alberta municipal debt comparison, dept KPIs, debt-by-currency composite display.

---

## Sequencing

- **P1 + P2 are the spine.** Until they ship, nothing about the platform reflects the spec's core principle. Do them back-to-back.
- **P3 can interleave with P2** (different tables, no conflict).
- **P4 unblocks P5 and P6** (compositions and crosswalk compat both need `aggregation_type`).
- **P7 and P8** are independent — pull either forward if priorities shift.
- All current `measure_citations` rows survive P1 as pending-review extracted_observations. Reviewers can batch-approve via P2 admin UI to backfill canonical_observations.

Estimated ~22 migrations total. Largest risk: P1 rename + backfill (touches every read path). Recommend a branch with full public-API test coverage before merging.
