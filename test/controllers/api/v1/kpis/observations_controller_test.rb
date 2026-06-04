require "test_helper"

class Api::V1::Kpis::ObservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @jur_a = Warehouse::Jurisdiction.find_or_create_by!(code: "OA-#{SecureRandom.hex(2)}") do |j|
      j.name = "OA"; j.slug = "oa-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @jur_b = Warehouse::Jurisdiction.find_or_create_by!(code: "OB-#{SecureRandom.hex(2)}") do |j|
      j.name = "OB"; j.slug = "ob-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @edmonton = Warehouse::Organization.create!(jurisdiction: @jur_a, slug: "ed-#{SecureRandom.hex(2)}", canonical_name: "Edmonton")
    @calgary  = Warehouse::Organization.create!(jurisdiction: @jur_b, slug: "ca-#{SecureRandom.hex(2)}", canonical_name: "Calgary")
    @doc_a = Warehouse::KpiDocument.create!(jurisdiction: @jur_a, organization: @edmonton, fiscal_year: 2024,
      doc_url: "https://example.com/oa-#{SecureRandom.hex(4)}.pdf")
    @doc_b = Warehouse::KpiDocument.create!(jurisdiction: @jur_b, organization: @calgary, fiscal_year: 2024,
      doc_url: "https://example.com/ob-#{SecureRandom.hex(4)}.pdf")
    @debt_e = Warehouse::Measure.create!(organization: @edmonton, slug: "debt-#{SecureRandom.hex(2)}",
      canonical_name: "Total debt", unit: @unit, category: "debt", aggregation_type: "additive")
    @debt_c = Warehouse::Measure.create!(organization: @calgary,  slug: "debt-#{SecureRandom.hex(2)}",
      canonical_name: "Total debt", unit: @unit, category: "debt", aggregation_type: "additive")

    @obs_e = approved(@debt_e, @doc_a, year: 2024, value: 5_000_000_000, org: @edmonton, jur: @jur_a)
    @obs_c = approved(@debt_c, @doc_b, year: 2024, value: 7_000_000_000, org: @calgary,  jur: @jur_b)
  end

  test "index returns approved canonical observations only" do
    pending = Warehouse::ExtractedObservation.create!(measure: @debt_e, document: @doc_a,
      measurement_year: 2025, value_type: "actual", value_numeric: 6_000_000_000)
    refute pending.canonical_observation

    get "/api/v1/kpis/observations"
    assert_response :success
    ids = JSON.parse(response.body)["data"].map { |o| o["id"] }
    assert_includes ids, @obs_e.canonical_observation.id
    assert_includes ids, @obs_c.canonical_observation.id
  end

  test "index filters by observed_organization_slug" do
    get "/api/v1/kpis/observations", params: { observed_organization_slug: @edmonton.slug }
    body = JSON.parse(response.body)
    assert(body["data"].all? { |o| o["observed_organization_id"] == @edmonton.id })
  end

  test "index filters by jurisdiction_slug" do
    get "/api/v1/kpis/observations", params: { jurisdiction_slug: @jur_b.slug }
    body = JSON.parse(response.body)
    assert(body["data"].all? { |o| o["jurisdiction_id"] == @jur_b.id })
  end

  test "index filters by measure_category" do
    other = Warehouse::Measure.create!(organization: @edmonton, slug: "non-debt-#{SecureRandom.hex(2)}",
      canonical_name: "Permits", unit: @unit, category: "permits", aggregation_type: "additive")
    approved(other, @doc_a, year: 2024, value: 1000, org: @edmonton, jur: @jur_a)

    get "/api/v1/kpis/observations", params: { measure_category: "debt" }
    body = JSON.parse(response.body)
    refute_empty body["data"]
    body["data"].each do |o|
      m = Warehouse::Measure.find(o["measure_id"])
      assert_equal "debt", m.category
    end
  end

  test "show returns one canonical observation with derivation_count" do
    canonical = @obs_e.canonical_observation
    get "/api/v1/kpis/observations/#{canonical.id}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal canonical.id, body["id"]
    assert_equal 0, body["derivation_count"]
  end

  test "derivations endpoint returns derived observations for an observation" do
    canonical = @obs_e.canonical_observation
    geo = Warehouse::GeoBoundary.create!(boundary_type: "csd", geo_uid: "C-#{SecureRandom.hex(3)}",
      province_code: "AB", census_year: 2021)
    set = Warehouse::GeographyCrosswalkSet.create!(name: "x", method: "manual", weight_basis: "manual",
      from_code_system: "x", to_code_system: "y")
    Warehouse::DerivedObservation.create!(measure: @debt_e, from_canonical_observation: canonical,
      crosswalk_set: set, derived_geo: geo, measurement_year: 2024,
      value_numeric: 1, derivation_method: "crosswalk_allocation", confidence: 0.9)

    get "/api/v1/kpis/observations/#{canonical.id}/derivations"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["data"].length
    assert_equal "crosswalk_allocation", body["data"].first["derivation_method"]
  end

  private

  def approved(measure, doc, year:, value:, org:, jur:)
    obs = Warehouse::ExtractedObservation.create!(measure: measure, document: doc,
      measurement_year: year, value_type: "actual", value_numeric: value,
      observed_organization: org, jurisdiction: jur)
    obs.approve!(reviewer: "test")
    obs
  end
end
