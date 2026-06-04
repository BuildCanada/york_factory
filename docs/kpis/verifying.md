# Verifying the KPI Platform

Concrete steps to convince yourself the spec's principles are enforced in the
code. Three layers: tests, console walkthrough, HTTP walkthrough.

## 1. The test suite

```bash
bin/rails test
# 507 runs, 1389 assertions, 0 failures, 0 errors, 0 skips
```

Phase-by-phase, the files that exercise each spec principle:

```bash
# Phase 1 — claim/canonical split + entity roles
bin/rails test test/models/warehouse/extracted_observation_test.rb \
               test/models/warehouse/canonical_observation_test.rb

# Phase 2 — review workflow (model + HTTP)
bin/rails test test/models/warehouse/observation_review_flag_test.rb \
               test/models/warehouse/review_workflow_test.rb \
               test/controllers/api/v1/kpis/admin/review_workflow_test.rb

# Phase 3 — footnotes + agent assertions
bin/rails test test/models/warehouse/footnotes_and_assertions_test.rb \
               test/controllers/api/v1/kpis/admin/footnotes_assertions_api_test.rb

# Phase 4 — metric versions + aliases + resolver
bin/rails test test/models/warehouse/metric_versions_and_aliases_test.rb

# Phase 5 — composite metrics + sum validation
bin/rails test test/models/warehouse/metric_compositions_test.rb

# Phase 6 — crosswalk sets + the "don't crosswalk a rate" guard
bin/rails test test/models/warehouse/crosswalks_v2_test.rb

# Phase 7 — alerts
bin/rails test test/models/warehouse/alerts_test.rb

# Phase 8 — public canonical API
bin/rails test test/controllers/api/v1/kpis/observations_controller_test.rb
```

If you want to map a specific spec rule to a test, the test name almost
always matches: e.g. spec §10.6 ("rates should not be directly allocated")
maps to `test_Allocator_refuses_to_crosswalk_non-aggregable_measures` in
`crosswalks_v2_test.rb`.

## 2. Console walkthrough

This is the fastest way to feel the shape of the pipeline. Each step
exercises one spec principle and prints state.

```bash
bin/rails console
```

```ruby
# Setup — a publisher (Alberta) reporting on a different entity (Edmonton).
jur_a   = Warehouse::Jurisdiction.find_or_create_by!(code: "AB", slug: "alberta",
            name: "Alberta", level: "provincial", fiscal_year_start_month: 4,
            default_currency: "CAD")
jur_e   = Warehouse::Jurisdiction.find_or_create_by!(code: "EDM", slug: "edmonton",
            name: "City of Edmonton", level: "municipal", fiscal_year_start_month: 1,
            default_currency: "CAD")
alberta = Warehouse::Organization.find_or_create_by!(jurisdiction: jur_a, slug: "ab-gov") {
            _1.canonical_name = "Government of Alberta" }
edmonton = Warehouse::Organization.find_or_create_by!(jurisdiction: jur_e, slug: "edmonton") {
            _1.canonical_name = "City of Edmonton" }
cad = Warehouse::Unit.find_or_create_by!(symbol: "CAD") {
        _1.kind = "absolute"; _1.base_unit = "dollars"; _1.scale = 1.0; _1.currency_code = "CAD" }

doc = Warehouse::KpiDocument.create!(jurisdiction: jur_a, organization: alberta,
        fiscal_year: 2024, doc_url: "https://example.com/ab-municipal-debt-2024.pdf")
debt = Warehouse::Measure.create!(organization: edmonton, slug: "total-debt",
        canonical_name: "Total debt", unit: cad, aggregation_type: "additive",
        category: "debt")

# (a) Agent posts a claim. Spec: three entity roles, raw labels, evidence.
claim = Warehouse::ExtractedObservation.create!(
  measure: debt, document: doc, measurement_year: 2024, value_type: "actual",
  value_numeric: 5_000_000_000,
  reporting_organization: alberta,     # who PUBLISHED
  responsible_organization: alberta,
  observed_organization: edmonton,     # who the metric is ABOUT
  jurisdiction: jur_e,                  # Edmonton's authority
  metric_name_raw: "Municipal debt",
  geography_name_raw: "City of Edmonton",
  source_page: 12,
  evidence_quote: "Edmonton: $5.0B tax-supported debt",
  extraction_confidence: 0.94,
  needs_review: true                    # surfaces in queue
)

# (b) Add an assertion + a flag.
claim.extraction_assertions.create!(assertion_type: "unit",
  assertion_text: "amounts in $ billions", confidence: 0.9, source_page: 12)
claim.review_flags.create!(flag_type: "unit_ambiguous", severity: "high",
  message: "Table label is ambiguous about billions vs millions")

# (c) Verify: it's a CLAIM, not a fact.
claim.review_status                     # => "pending"
claim.canonical_observation             # => nil
Warehouse::MeasureFact.where(measure_id: debt.id).count  # => 0  (facts read canonical only)

# (d) Queue surfaces it.
Warehouse::HumanReviewQueueEntry.find(claim.id).highest_open_severity  # => "high"

# (e) Reviewer approves with an edit.
claim.approve!(reviewer: "alice", new_value: { "value_numeric" => 5_100_000_000 })

# (f) Verify: now it's a fact, flag is auto-resolved, decision is recorded.
claim.reload.review_status              # => "approved"
claim.open_review_flags.count           # => 0
claim.review_decisions.last.decision    # => "edited"
claim.canonical_observation.value_numeric  # => 5_100_000_000.0
Warehouse::MeasureFact.where(measure_id: debt.id).count  # => 1

# (g) Spec rule: rates can't be crosswalked. Set up a non-aggregable measure
#     and watch the allocator refuse.
rate = Warehouse::Measure.create!(organization: edmonton, slug: "unemployment",
  canonical_name: "Unemployment rate", unit: cad, aggregation_type: "non_aggregable")
geo_da = Warehouse::GeoBoundary.create!(boundary_type: "da", geo_uid: "DA1",
  census_year: 2021, province_code: "AB")
geo_csd = Warehouse::GeoBoundary.create!(boundary_type: "csd", geo_uid: "CSD1",
  census_year: 2021, province_code: "AB")
rate_obs = Warehouse::ExtractedObservation.create!(measure: rate, document: doc,
  measurement_year: 2024, value_type: "actual", value_numeric: 7.5,
  geo_boundary: geo_da)
rate_obs.approve!(reviewer: "alice")

set = Warehouse::GeographyCrosswalkSet.create!(name: "DA→CSD",
  method: "tabular", weight_basis: "population",
  from_code_system: "da_2021", to_code_system: "csd_2021")
set.entries.create!(from_geo: geo_da, to_geo: geo_csd, weight: 0.5,
  relationship_type: "allocated")

begin
  Warehouse::GeographyCrosswalkSet::Allocator.allocate!(
    crosswalk_set: set, canonical_observation: rate_obs.canonical_observation,
    target_geo: geo_csd)
rescue Warehouse::GeographyCrosswalkSet::Allocator::IncompatibleMetric => e
  puts "blocked: #{e.message}"
end
# => "blocked: measure aggregation_type=non_aggregable cannot be directly crosswalked..."

# (h) Same call, with explicit compatibility row → allowed.
Warehouse::CrosswalkMetricCompatibility.create!(crosswalk_set: set, measure: rate,
  compatibility: "risky", reason: "manual override for demo")
result = Warehouse::GeographyCrosswalkSet::Allocator.allocate!(
  crosswalk_set: set, canonical_observation: rate_obs.canonical_observation,
  target_geo: geo_csd)
result.derived.value_numeric            # => 3.75
result.derived.derivation_method        # => "crosswalk_allocation"
```

What the walkthrough proves:
- (c) facts read canonical only — agent output is not truth
- (d) queue surfaces only pending + flagged/needs_review claims
- (e)/(f) approval is atomic: state + canonical + flag-resolution + decision
- (g) non-aggregable measures are blocked from crosswalk allocation
- (h) the block is overridable explicitly, with audit trail

## 3. HTTP walkthrough

```bash
# Issue an admin token in console first:
# Warehouse::ApiToken.issue!(name: "verify", scopes: ["kpis:write"])
TOKEN=…

# Pull pending review items.
curl -s "http://localhost:3000/api/v1/kpis/admin/review_queue?min_severity=high" \
  -H "Authorization: Bearer $TOKEN" | jq

# Flag an observation.
curl -s -X POST \
  "http://localhost:3000/api/v1/kpis/admin/extracted_observations/$ID/review_flags" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"flag_type":"unit_ambiguous","severity":"high","message":"check $B vs $M"}'

# Approve with an edit.
curl -s -X POST \
  "http://localhost:3000/api/v1/kpis/admin/extracted_observations/$ID/approve" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"reviewer":"alice","new_value":{"value_numeric":5100000000}}'

# Confirm it's now in the public canonical feed.
curl -s "http://localhost:3000/api/v1/kpis/observations?observed_organization_slug=edmonton" | jq

# And that derivations are reachable per fact.
curl -s "http://localhost:3000/api/v1/kpis/observations/$CANONICAL_ID/derivations" | jq
```

## 4. Schema sanity checks

```bash
# All migrations applied.
bin/rails db:migrate:status | grep down   # should print nothing

# Phase 1: extracted_observations table has the new columns.
bin/rails runner 'puts Warehouse::ExtractedObservation.column_names.sort'
# Expect: extraction_confidence, evidence_quote, geo_boundary_id,
#         jurisdiction_id, needs_review, observed_organization_id,
#         period_end, period_start, period_type, reporting_organization_id,
#         responsible_organization_id, review_status, source_chart,
#         source_section, source_table, value_raw, ...

# Phase 2: human_review_queue view exists.
bin/rails runner 'puts Warehouse::HumanReviewQueueEntry.connection.execute(
  "SELECT to_regclass(%q(warehouse.human_review_queue))").first'

# Phase 6: crosswalk_weight_checks view exists.
bin/rails runner 'puts Warehouse::Record.connection.execute(
  "SELECT to_regclass(%q(warehouse.crosswalk_weight_checks))").first'

# Phase 4: ratio measures without numerator/denominator are rejected.
bin/rails runner '
  m = Warehouse::Measure.first
  begin
    m.connection.execute("UPDATE warehouse.measures SET aggregation_type=%q(ratio) WHERE id=#{m.id}")
    puts "MISSED constraint"
  rescue ActiveRecord::StatementInvalid
    puts "constraint working"
  end
'
```

## 5. Lint

```bash
bundle exec rubocop app/models/warehouse app/controllers/api/v1/kpis \
                    test/models/warehouse test/controllers/api/v1/kpis \
                    db/migrate/2026052[78]*
# Expect: no offenses
```
