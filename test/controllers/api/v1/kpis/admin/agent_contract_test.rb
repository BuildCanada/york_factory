require "test_helper"

# End-to-end coverage of the spec §13 agent contract documented in
# docs/kpis/agent_contract.md. POSTs the full per-observation payload to
# /api/v1/kpis/admin/citations, then verifies:
#   1. every documented field is persisted on the extracted_observation row
#   2. footnotes can be created on the document and linked
#   3. extraction_assertions can be attached
#   4. review_flags surface in the queue
#   5. approve! propagates entity roles, geo, jurisdiction, composition,
#      evidence-period to the canonical_observation
#   6. the public /observations endpoint returns the canonical fields
class Api::V1::Kpis::Admin::AgentContractTest < ActionDispatch::IntegrationTest
  setup do
    @reporting_jur = Warehouse::Jurisdiction.find_or_create_by!(code: "AC-AB") do |j|
      j.name = "Alberta"; j.slug = "ac-alberta-#{SecureRandom.hex(2)}"
      j.level = "provincial"; j.fiscal_year_start_month = 4; j.default_currency = "CAD"
    end
    @observed_jur = Warehouse::Jurisdiction.find_or_create_by!(code: "AC-EDM") do |j|
      j.name = "City of Edmonton"; j.slug = "ac-edmonton-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @reporting_org = Warehouse::Organization.create!(jurisdiction: @reporting_jur,
      slug: "ac-ab-gov-#{SecureRandom.hex(2)}", canonical_name: "Government of Alberta")
    @observed_org = Warehouse::Organization.create!(jurisdiction: @observed_jur,
      slug: "ac-edmonton-#{SecureRandom.hex(2)}", canonical_name: "City of Edmonton")

    @unit = Warehouse::Unit.find_or_create_by!(symbol: "CAD") {
      _1.kind = "absolute"; _1.base_unit = "dollars"; _1.scale = 1.0; _1.currency_code = "CAD"
    }
    @geo = Warehouse::GeoBoundary.create!(boundary_type: "csd",
      geo_uid: "ED-CSD-#{SecureRandom.hex(3)}", province_code: "AB", census_year: 2021)

    @doc = Warehouse::KpiDocument.create!(jurisdiction: @reporting_jur, organization: @reporting_org,
      fiscal_year: 2024,
      doc_url: "https://example.com/ac-#{SecureRandom.hex(4)}.pdf",
      doc_title: "Alberta Municipal Financials 2024",
      published_at: Date.new(2024, 6, 1),
      published_at_source: "pdf_metadata")
    @measure = Warehouse::Measure.create!(organization: @observed_org,
      slug: "total-debt-#{SecureRandom.hex(2)}", canonical_name: "Total debt",
      unit: @unit, aggregation_type: "additive", category: "debt", frequency: "annual",
      higher_is_bad: true, description: "Municipal tax-supported debt")
    @metric_version = Warehouse::MetricVersion.create!(measure: @measure,
      version_label: "2024 methodology", definition: "Tax-supported debt under the 2024 methodology")
    @composition = Warehouse::MetricComposition.create!(measure: @measure,
      composition_type: "by_debt_type", name: "Debt by type")
    @component = Warehouse::MetricComponent.create!(measure: @measure, composition: @composition,
      component_type: "debt_type", component_code: "tax_supported", component_name: "Tax-supported debt")

    @run = Warehouse::AgentRun.create!(agent_name: "extract-kpis", agent_version: "1.0.0",
      status: "running", started_at: Time.current)

    @raw_token = Warehouse::ApiToken.issue!(name: "ac-#{SecureRandom.hex(2)}", scopes: [ "kpis:write" ])
  end

  test "full spec §13 payload round-trips through claim → canonical → public read" do
    # ---- (1) Agent POSTs a claim with every documented field. ----
    payload = {
      agent_run_id: @run.id,
      citations: [ {
        measure_id: @measure.id, document_id: @doc.id,
        measurement_year: 2024, value_type: "actual", period_basis: "full_year",
        period_start: "2024-01-01", period_end: "2024-12-31", period_type: "calendar_year",
        period_label_raw: "FY2024",
        metric_version_id: @metric_version.id,
        composition_id: @composition.id,
        component_id: @component.id,
        value_numeric: 5_000_000_000, value_text: nil, value_raw: "$5.0B", unit_raw: "CAD billions",

        metric_name_raw: "Municipal debt",
        geography_name_raw: "City of Edmonton",
        jurisdiction_name_raw: "City of Edmonton municipal jurisdiction",
        reporting_organization_raw: "Government of Alberta",
        responsible_organization_raw: "Alberta Municipal Affairs",
        observed_organization_raw: "City of Edmonton",

        reporting_organization_id: @reporting_org.id,
        responsible_organization_id: @reporting_org.id,
        observed_organization_id: @observed_org.id,
        geo_boundary_id: @geo.id,
        jurisdiction_id: @observed_jur.id,

        source_page: 12, source_section: "Municipal Debt Tables",
        source_table: "Table 3.1", source_chart: nil,
        evidence_quote: "Edmonton: $5.0B tax-supported debt as of fiscal year-end 2024",
        extraction_confidence: 0.94, needs_review: true,
        notes: "Restated from prior year per footnote 1"
      } ]
    }

    post "/api/v1/kpis/admin/citations", params: payload, headers: auth_headers
    assert_response :success
    obs_id = JSON.parse(response.body).fetch("ids").first
    obs = Warehouse::ExtractedObservation.find(obs_id)

    # ---- (2) Every documented field landed verbatim. ----
    assert_equal @measure.id,                       obs.measure_id
    assert_equal @doc.id,                           obs.document_id
    assert_equal @run.id,                           obs.agent_run_id
    assert_equal 2024,                              obs.measurement_year
    assert_equal "actual",                          obs.value_type
    assert_equal "full_year",                       obs.period_basis
    assert_equal Date.new(2024, 1, 1),              obs.period_start
    assert_equal Date.new(2024, 12, 31),            obs.period_end
    assert_equal "calendar_year",                   obs.period_type
    assert_equal "FY2024",                          obs.period_label_raw
    assert_equal @metric_version.id,                obs.metric_version_id
    assert_equal @composition.id,                   obs.composition_id
    assert_equal @component.id,                     obs.component_id
    assert_equal 5_000_000_000.0,                   obs.value_numeric
    assert_equal "$5.0B",                           obs.value_raw
    assert_equal "CAD billions",                    obs.unit_raw
    assert_equal "Municipal debt",                  obs.metric_name_raw
    assert_equal "City of Edmonton",                obs.geography_name_raw
    assert_equal "Alberta Municipal Affairs",       obs.responsible_organization_raw
    assert_equal "City of Edmonton",                obs.observed_organization_raw
    assert_equal @reporting_org.id,                 obs.reporting_organization_id
    assert_equal @reporting_org.id,                 obs.responsible_organization_id
    assert_equal @observed_org.id,                  obs.observed_organization_id
    assert_equal @geo.id,                           obs.geo_boundary_id
    assert_equal @observed_jur.id,                  obs.jurisdiction_id
    assert_equal 12,                                obs.source_page
    assert_equal "Municipal Debt Tables",           obs.source_section
    assert_equal "Table 3.1",                       obs.source_table
    assert_match /tax-supported debt/,              obs.evidence_quote
    assert_in_delta 0.94,                           obs.extraction_confidence, 1e-6
    assert obs.needs_review
    assert_equal "pending",                         obs.review_status

    # ---- (3) Footnote creation + link via the documented endpoint. ----
    post "/api/v1/kpis/admin/documents/#{@doc.id}/footnotes",
      params: { footnote_text: "Restated from prior year per accounting policy change",
                page: 12, marker: "1", agent_run_id: @run.id },
      headers: auth_headers
    assert_response :created
    footnote_id = JSON.parse(response.body).fetch("id")

    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/footnote_links",
      params: { source_footnote_id: footnote_id }, headers: auth_headers
    assert_response :created
    assert_equal 1, obs.reload.source_footnotes.count
    assert_equal "Restated from prior year per accounting policy change",
                 obs.source_footnotes.first.footnote_text

    # ---- (4) Assertion attached via the documented endpoint. ----
    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/assertions",
      params: { assertion_type: "unit",
                assertion_text: "Value reported in dollars billions, multiplied to dollars for storage",
                confidence: 0.9, evidence_quote: "Header: amounts shown in $billions",
                source_page: 12 },
      headers: auth_headers
    assert_response :created
    assertion = obs.extraction_assertions.first
    assert_equal "unit",      assertion.assertion_type
    assert_in_delta 0.9,      assertion.confidence, 1e-6

    # ---- (5) Flag surfaces in the queue. ----
    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/review_flags",
      params: { flag_type: "possible_total_vs_per_capita_confusion",
                severity: "high",
                message: "Document mixes municipal-government debt and per-capita figures" },
      headers: auth_headers
    assert_response :created

    get "/api/v1/kpis/admin/review_queue", headers: auth_headers
    queue = JSON.parse(response.body)["data"]
    row = queue.find { |r| r["extracted_observation_id"] == obs.id }
    assert_not_nil row, "observation should appear in review queue"
    assert_equal "high", row["highest_open_severity"]
    assert_equal 1,      row["open_flag_count"]
    assert_equal "Municipal debt", row["metric_name_raw"]
    assert_match /tax-supported debt/, row["evidence_quote"]

    # ---- (6) Approve and confirm propagation to canonical_observation. ----
    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/approve",
      params: { reviewer: "alice", notes: "Verified against StatsCan crosswalk" },
      headers: auth_headers
    assert_response :success

    canonical = obs.reload.canonical_observation
    refute_nil canonical
    assert_equal @reporting_org.id, canonical.reporting_organization_id
    assert_equal @reporting_org.id, canonical.responsible_organization_id
    assert_equal @observed_org.id,  canonical.observed_organization_id
    assert_equal @geo.id,           canonical.geo_boundary_id
    assert_equal @observed_jur.id,  canonical.jurisdiction_id
    assert_equal @metric_version.id, canonical.metric_version_id
    assert_equal @composition.id,    canonical.composition_id
    assert_equal @component.id,      canonical.component_id
    assert_equal 5_000_000_000.0,   canonical.value_numeric
    assert_equal Date.new(2024, 1, 1),  canonical.period_start
    assert_equal Date.new(2024, 12, 31), canonical.period_end
    assert_equal "calendar_year",   canonical.period_type
    assert_equal @unit.id,          canonical.unit_id    # inherited from measure
    assert_equal "reported",        canonical.status
    assert_equal "alice",           canonical.approved_by
    assert_equal Date.new(2024, 6, 1), canonical.vintage_date.to_date  # from document.published_at
    assert_equal 0, obs.open_review_flags.count                # flag auto-resolved
    assert_equal "approved", obs.review_decisions.last.decision

    # ---- (7) Public canonical endpoint exposes the fact with all entity roles. ----
    get "/api/v1/kpis/observations", params: { observed_organization_slug: @observed_org.slug }
    assert_response :success
    record = JSON.parse(response.body)["data"].find { |r| r["id"] == canonical.id }
    refute_nil record, "approved observation should appear in public /observations"
    assert_equal @reporting_org.id, record["reporting_organization_id"]
    assert_equal @observed_org.id,  record["observed_organization_id"]
    assert_equal @observed_jur.id,  record["jurisdiction_id"]
    assert_equal @geo.id,           record["geo_boundary_id"]
    assert_equal 5_000_000_000.0,   record["value_numeric"]
    assert_equal "2024-01-01",      record["period_start"]
    assert_equal "2024-12-31",      record["period_end"]
    assert_equal "Total debt",      record["measure_name"]
    assert_equal "reported",        record["status"]
  end

  test "contract dedupes on the full spec key including composition + entity context" do
    base = {
      measure_id: @measure.id, document_id: @doc.id,
      measurement_year: 2024, value_type: "actual", period_basis: "full_year",
      value_numeric: 100,
      observed_organization_id: @observed_org.id,
      geo_boundary_id: @geo.id
    }

    post "/api/v1/kpis/admin/citations",
      params: { citations: [ base, base ] }, headers: auth_headers
    body = JSON.parse(response.body)
    assert_equal 1, body["inserted"], "second identical row should be deduped"
    assert_equal 1, body["skipped_duplicate"]

    # Changing observed_organization makes it a distinct fact (cross-jurisdiction case).
    other_org = Warehouse::Organization.create!(jurisdiction: @reporting_jur,
      slug: "ac-other-#{SecureRandom.hex(2)}", canonical_name: "Other municipality")
    distinct = base.merge(observed_organization_id: other_org.id)
    post "/api/v1/kpis/admin/citations",
      params: { citations: [ distinct ] }, headers: auth_headers
    assert_equal 1, JSON.parse(response.body)["inserted"]
  end

  test "citation endpoint rejects legacy skill field names instead of silently dropping evidence" do
    post "/api/v1/kpis/admin/citations",
      params: { citations: [ {
        measure_id: @measure.id,
        document_id: @doc.id,
        measurement_year: 2024,
        value_type: "actual",
        value_numeric: 1,
        value_raw_text: "$1",
        page_number: 7
      } ] },
      headers: auth_headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "unsupported_citation_fields", body["error"]
    assert_equal({ "page_number" => "source_page", "value_raw_text" => "value_raw" },
      body["replacements"])
    assert_equal 0, Warehouse::ExtractedObservation.where(document_id: @doc.id, value_numeric: 1).count
  end

  test "citation endpoint returns a 422 for missing required fields" do
    post "/api/v1/kpis/admin/citations",
      params: { citations: [ {
        document_id: @doc.id,
        measurement_year: 2024,
        value_type: "actual",
        value_numeric: 1
      } ] },
      headers: auth_headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_citation", body["error"]
    assert_match /measure_id/, body["details"]
  end

  test "review_flag endpoint rejects payload missing required fields (negative path)" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)

    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/review_flags",
      params: { severity: "low" },                # missing flag_type + message
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "assertions endpoint rejects confidence outside [0,1]" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)

    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/assertions",
      params: { assertion_type: "unit", assertion_text: "x", confidence: 1.5 },
      headers: auth_headers
    assert_response :unprocessable_entity
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@raw_token}" }
  end
end
