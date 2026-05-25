require "test_helper"

class Api::V1::Kpis::ApiTest < ActionDispatch::IntegrationTest
  setup do
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "TOR-ON") do |j|
      j.name = "City of Toronto"
      j.slug = "toronto"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.find_or_create_by!(jurisdiction_id: @jurisdiction.id, slug: "test-org-#{SecureRandom.hex(2)}") do |o|
      o.canonical_name = "Test Org #{SecureRandom.hex(2)}"
    end
    @doc = Warehouse::KpiDocument.create!(
      jurisdiction: @jurisdiction,
      organization: @org,
      fiscal_year: 2024,
      doc_url: "https://example.com/test-#{SecureRandom.hex(4)}.pdf",
      doc_title: "Test Doc",
      published_at: Date.new(2024, 3, 1)
    )
    @measure = Warehouse::Measure.create!(
      organization: @org,
      slug: "test-measure-#{SecureRandom.hex(2)}",
      canonical_name: "Test Measure",
      unit: @unit
    )
    Warehouse::MeasureCitation.create!(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 100
    )
  end

  test "GET /api/v1/kpis/jurisdictions returns the seeded jurisdiction" do
    get "/api/v1/kpis/jurisdictions"
    assert_response :success
    body = JSON.parse(response.body)
    slugs = body["data"].map { |j| j["slug"] }
    assert_includes slugs, "toronto"
  end

  test "GET /api/v1/kpis/jurisdictions/:slug/organizations lists orgs" do
    get "/api/v1/kpis/jurisdictions/toronto/organizations"
    assert_response :success
    body = JSON.parse(response.body)
    slugs = body["data"].map { |o| o["slug"] }
    assert_includes slugs, @org.slug
  end

  test "GET /api/v1/kpis/measures filters by organization_slug" do
    get "/api/v1/kpis/measures", params: { organization_slug: @org.slug }
    assert_response :success
    body = JSON.parse(response.body)
    assert(body["data"].any? { |m| m["id"] == @measure.id })
  end

  test "GET /api/v1/kpis/measures/:id/facts returns resolved facts" do
    get "/api/v1/kpis/measures/#{@measure.id}/facts"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["data"].length
    assert_equal "actual", body["data"][0]["value_type"]
    assert_equal 100.0, body["data"][0]["value_numeric"]
  end

  test "GET /api/v1/kpis/measures/:id/citations returns citations with document info" do
    get "/api/v1/kpis/measures/#{@measure.id}/citations"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["data"].length
    assert_equal @doc.doc_url, body["data"][0]["document"]["doc_url"]
  end

  test "404 on unknown jurisdiction slug" do
    get "/api/v1/kpis/jurisdictions/nope-#{SecureRandom.hex(2)}/organizations"
    assert_response :not_found
  end
end
