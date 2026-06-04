# KPI Platform — Architecture

Implementation of the spec in `platform_plan.md`. Eight phases, all in the
`warehouse` Postgres schema, all reachable from `app/models/warehouse/*` and
`app/controllers/api/v1/kpis/*`.

## The pipeline at a glance

```
PDF / report / dataset
        │
        ▼
sources + raw_ingestions             ← archival + fetch metadata
        │
        ▼
kpi_documents (per agent_run)        ← what the agent saw
        │
        ▼
extracted_observations  ──┐          ← agent CLAIMS (review_status='pending')
  ├─ extraction_assertions │
  ├─ observation_footnotes ├─ Phase 3
  ├─ review_flags ─────────┤
  └─ review_decisions ─────┤         ← typed flags, severity, resolution
                           │
        ▼ approve!         │
                           │
canonical_observations  ◄──┘         ← TRUSTED facts (Phase 1)
        │
   ┌────┼────┬──────────────┐
   ▼    ▼    ▼              ▼
 facts   composition         derived_observations
 view    _validation         (crosswalk_allocation,
 (P1)    _results (P5)       aggregation, rebase, …)
   │                               (P6)
   ▼
public /observations endpoint (P8)
```

A claim becomes a fact only via `ExtractedObservation#approve!` — there is
no admin endpoint that writes to `canonical_observations` directly.

## Key tables (by phase)

| Phase | Tables / views | Purpose |
|---|---|---|
| **1** | `extracted_observations`, `canonical_observations`, `measure_facts` (view) | Claim/fact split + 3 entity roles + evidence |
| **2** | `observation_review_flags`, `review_decisions`, `human_review_queue` (view) | Audited approve/reject workflow |
| **3** | `source_footnotes`, `observation_footnotes`, `extraction_assertions` | First-class footnotes + agent reasoning |
| **4** | `metric_versions`, `metric_aliases`, new `measures.*` columns | Definition drift + raw-text resolver + cross-jurisdiction equivalence |
| **5** | `metric_compositions`, `metric_components`, `metric_component_relationships`, `composition_validation_results` | Composite metrics (currency exposure, revenue by source) |
| **6** | `geography_crosswalk_sets`, `geography_crosswalk_entries`, `crosswalk_metric_compatibility`, `derived_observations`, `crosswalk_weight_checks` (view) | Geo versioning + safe crosswalking |
| **7** | `alerts`, `alert_events` | SQL-first alerting against canonical |
| **8** | `dashboard_observations` (view) + new `/observations` API | Public read layer |

## Where the spec's core rules live

| Spec rule | Where it's enforced |
|---|---|
| Agent outputs are claims, not facts | `extracted → canonical_observations` separation; only `ExtractedObservation#approve!` creates a canonical row |
| 3 entity roles per observation | `{reporting,responsible,observed}_organization_id` columns on both observation tables |
| Geography ≠ jurisdiction ≠ entity | `geo_boundaries` / `jurisdictions` / `organizations` — separate tables, separate FKs on observations |
| Don't crosswalk a rate directly | `Warehouse::GeographyCrosswalkSet::Allocator#guard_compatibility!` — raises `IncompatibleMetric` unless aggregation_type ∈ {additive, semi_additive} or an explicit `crosswalk_metric_compatibility` row says otherwise |
| Composite metrics use composition/component, not separate measures | `composition_id` + `component_id` on observations; validator runs sum-to-total + sum-to-100 |
| Reported aggregates ≠ derived aggregates | `is_total` flag on `canonical_observations` for reported rollups; `derived_observations` with `derivation_method='aggregation'` for computed |
| Cross-jurisdiction comparison without dropping organization_id | `metric_aliases.kind='measure_equivalence'` links org-scoped measures to a canonical one; `Measure#canonical_equivalent` follows it |
| Definition normalization is honest | No `derivation_method='definition_normalization'` shortcut wired up by default — measures stay separate unless an alias explicitly equates them |

## Models you'll touch most

- `Warehouse::ExtractedObservation` — the claim. `approve!` / `reject!` / `promote_to_canonical!` / `open_review_flags`.
- `Warehouse::CanonicalObservation` — the fact. Read-only from the public API.
- `Warehouse::ObservationReviewFlag` — typed, severity, `resolve!`.
- `Warehouse::Measure` — has `aggregation_type`, `canonical_equivalent`, alias chain.
- `Warehouse::Measure::Resolver` — alias → canonical_name → slug for the agent.
- `Warehouse::MetricComposition::Validator` — composition integrity.
- `Warehouse::GeographyCrosswalkSet::Allocator` — derived observation creation with guard.
- `Warehouse::Alert::Evaluator` — alert evaluation.

## Reviewer workflow

```
1. Agent runs and POSTs observations to /api/v1/kpis/admin/citations
   (creates extracted_observations with review_status='pending')

2. Agent attaches per-fact context:
   - POST /api/v1/kpis/admin/extracted_observations/:id/assertions
   - POST /api/v1/kpis/admin/extracted_observations/:id/review_flags
   - POST /api/v1/kpis/admin/extracted_observations/:id/footnote_links

3. Reviewer pulls the queue:
   GET /api/v1/kpis/admin/review_queue?min_severity=high

4. Reviewer acts:
   POST /api/v1/kpis/admin/extracted_observations/:id/approve
        { reviewer, notes?, new_value? }       → promote to canonical
   POST /api/v1/kpis/admin/extracted_observations/:id/reject
        { reviewer, notes? }                   → no canonical row created

5. Approve transactionally:
   - flips review_status to 'approved'
   - copies into canonical_observations
   - resolves all open review_flags
   - records a review_decision (approved | edited if new_value supplied)
```

## What lives where in the repo

```
db/migrate/2026052[78]*.rb       — Phase 1-8 migrations (13 total)
app/models/warehouse/            — models + per-model service objects
  extracted_observation.rb
  canonical_observation.rb
  observation_review_flag.rb
  review_decision.rb
  source_footnote.rb / observation_footnote.rb / extraction_assertion.rb
  metric_version.rb / metric_alias.rb
  metric_composition.rb / metric_component.rb / …
  geography_crosswalk_set.rb (+ allocator subdir)
  derived_observation.rb / crosswalk_metric_compatibility.rb
  alert.rb (+ evaluator subdir) / alert_event.rb
  human_review_queue_entry.rb     (read-only view-backed)
  measure_fact.rb                 (read-only view-backed)
app/controllers/api/v1/kpis/
  observations_controller.rb       (Phase 8 public)
  admin/
    extracted_observations_controller.rb     (approve/reject)
    observation_review_flags_controller.rb
    extraction_assertions_controller.rb
    observation_footnotes_controller.rb
    source_footnotes_controller.rb
    review_queue_controller.rb
docs/kpis/
  platform_plan.md     — the plan (this implements)
  architecture.md      — this file
  agent_contract.md    — what the agent must emit (spec §13)
  verifying.md         — step-by-step verification (next file)
```
