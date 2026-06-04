require "test_helper"

class Api::V1::Kpis::PublicEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "PE-#{SecureRandom.hex(2)}") do |j|
      j.name = "PubEndpoints"; j.slug = "pe-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }

    @org_a = Warehouse::Organization.create!(jurisdiction: @jurisdiction, slug: "pe-a-#{SecureRandom.hex(2)}", canonical_name: "PE Org A")
    @org_b = Warehouse::Organization.create!(jurisdiction: @jurisdiction, slug: "pe-b-#{SecureRandom.hex(2)}", canonical_name: "PE Org B")

    @doc_a = Warehouse::KpiDocument.create!(jurisdiction: @jurisdiction, organization: @org_a,
      fiscal_year: 2024, doc_url: "https://example.com/pe-a-#{SecureRandom.hex(4)}.pdf",
      doc_title: "PE Doc A", published_at: Date.new(2024, 3, 1))
    @doc_b = Warehouse::KpiDocument.create!(jurisdiction: @jurisdiction, organization: @org_b,
      fiscal_year: 2025, doc_url: "https://example.com/pe-b-#{SecureRandom.hex(4)}.pdf",
      doc_title: "PE Doc B", published_at: Date.new(2025, 3, 1))

    @measure_a = Warehouse::Measure.create!(organization: @org_a, slug: "pe-ma-#{SecureRandom.hex(2)}",
      canonical_name: "PE Measure A", unit: @unit)
    @measure_b = Warehouse::Measure.create!(organization: @org_b, slug: "pe-mb-#{SecureRandom.hex(2)}",
      canonical_name: "PE Measure B", unit: @unit)

    @composition_a = Warehouse::MetricComposition.create!(measure: @measure_a,
      composition_type: "by_service_channel", name: "By service channel")
    @online_component = Warehouse::MetricComponent.create!(measure: @measure_a,
      composition: @composition_a, component_type: "service_channel", component_code: "online",
      component_name: "Online", sort_order: 1)
    @phone_component = Warehouse::MetricComponent.create!(measure: @measure_a,
      composition: @composition_a, component_type: "service_channel", component_code: "phone",
      component_name: "Phone", sort_order: 2)
    @composition_b = Warehouse::MetricComposition.create!(measure: @measure_b,
      composition_type: "by_region", name: "By region")
    Warehouse::MetricComponent.create!(measure: @measure_b,
      composition: @composition_b, component_type: "region", component_code: "north",
      component_name: "North")

    [
      Warehouse::ExtractedObservation.create!(measure: @measure_a, document: @doc_a,
        measurement_year: 2024, value_type: "actual", value_numeric: 100),
      Warehouse::ExtractedObservation.create!(measure: @measure_a, document: @doc_a,
        measurement_year: 2024, value_type: "target", value_numeric: 90),
      Warehouse::ExtractedObservation.create!(measure: @measure_b, document: @doc_b,
        measurement_year: 2025, value_type: "actual", value_numeric: 200)
    ].each { |o| o.promote_to_canonical!(approved_by: "test") }

    @org_lineage = Warehouse::OrganizationLineage.create!(
      predecessor: @org_a, successor: @org_b, transition_year: 2024, transition_kind: "rename",
      notes: "merged into B"
    )
    @measure_lineage = Warehouse::MeasureLineage.create!(
      predecessor: @measure_a, successor: @measure_b, transition_year: 2025, transition_kind: "methodology_revision"
    )
  end

  # --- documents ---

  test "GET /documents lists with filters" do
    get "/api/v1/kpis/documents", params: { jurisdiction_slug: @jurisdiction.slug }
    assert_response :success
    ids = JSON.parse(response.body)["data"].map { |d| d["id"] }
    assert_includes ids, @doc_a.id
    assert_includes ids, @doc_b.id
  end

  test "GET /documents filters by fiscal_year + organization_slug" do
    get "/api/v1/kpis/documents", params: { fiscal_year: 2024, organization_slug: @org_a.slug }
    body = JSON.parse(response.body)
    ids = body["data"].map { |d| d["id"] }
    assert_includes ids, @doc_a.id
    refute_includes ids, @doc_b.id
  end

  test "GET /documents/:id includes citation and measure counts" do
    get "/api/v1/kpis/documents/#{@doc_a.id}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["citation_count"]
    assert_equal 1, body["measure_count"]
  end

  # --- top-level citations ---

  test "GET /citations top-level filters by jurisdiction" do
    get "/api/v1/kpis/citations", params: { jurisdiction_slug: @jurisdiction.slug }
    assert_response :success
    assert_equal 3, JSON.parse(response.body)["data"].length
  end

  test "GET /citations filters by document_id" do
    get "/api/v1/kpis/citations", params: { document_id: @doc_a.id }
    assert_response :success
    rows = JSON.parse(response.body)["data"]
    assert_equal 2, rows.length
    assert rows.all? { |r| r["document"]["id"] == @doc_a.id }
  end

  test "GET /citations filters by value_type + year combo" do
    get "/api/v1/kpis/citations", params: { value_type: "target", year: 2024 }
    rows = JSON.parse(response.body)["data"]
    assert(rows.all? { |r| r["value_type"] == "target" && r["measurement_year"] == 2024 })
  end

  test "GET /measures/:id/citations (nested) still works" do
    get "/api/v1/kpis/measures/#{@measure_a.id}/citations"
    assert_response :success
    assert_equal 2, JSON.parse(response.body)["data"].length
  end

  # --- compositions ---

  test "GET /compositions filters by organization_slug" do
    get "/api/v1/kpis/compositions", params: { organization_slug: @org_a.slug }
    assert_response :success

    rows = JSON.parse(response.body)["data"]
    ids = rows.map { |row| row["id"] }
    assert_includes ids, @composition_a.id
    refute_includes ids, @composition_b.id

    row = rows.find { |r| r["id"] == @composition_a.id }
    assert_equal @measure_a.id, row["measure"]["id"]
    assert_equal "by_service_channel", row["composition_type"]
    assert_equal [ @online_component.id, @phone_component.id ], row["components"].map { |c| c["id"] }
  end

  test "GET /measures/:id/compositions returns components for one measure" do
    get "/api/v1/kpis/measures/#{@measure_a.id}/compositions"
    assert_response :success

    rows = JSON.parse(response.body)["data"]
    assert_equal [ @composition_a.id ], rows.map { |row| row["id"] }
    component = rows.first["components"].first
    assert_equal @online_component.id, component["id"]
    assert_equal "service_channel", component["component_type"]
    assert_equal "online", component["component_code"]
  end

  # --- top-level facts ---

  test "GET /facts top-level returns cross-measure facts" do
    get "/api/v1/kpis/facts", params: { jurisdiction_slug: @jurisdiction.slug }
    assert_response :success
    rows = JSON.parse(response.body)["data"]
    assert rows.length >= 3
  end

  test "GET /facts filters by organization + year" do
    get "/api/v1/kpis/facts", params: { organization_slug: @org_a.slug, year: 2024 }
    rows = JSON.parse(response.body)["data"]
    assert rows.all? { |r| r["measurement_year"] == 2024 }
  end

  # --- lineages ---

  test "GET /organization_lineages returns lineage rows with pred + succ" do
    get "/api/v1/kpis/organization_lineages", params: { predecessor_slug: @org_a.slug }
    assert_response :success
    rows = JSON.parse(response.body)["data"]
    assert_equal 1, rows.length
    assert_equal @org_a.slug, rows.first["predecessor"]["slug"]
    assert_equal @org_b.slug, rows.first["successor"]["slug"]
    assert_equal "rename", rows.first["transition_kind"]
  end

  test "GET /organization_lineages filters by jurisdiction" do
    get "/api/v1/kpis/organization_lineages", params: { jurisdiction_slug: @jurisdiction.slug }
    rows = JSON.parse(response.body)["data"]
    assert rows.any? { |r| r["id"] == @org_lineage.id }
  end

  test "GET /measure_lineages returns measure lineage rows" do
    get "/api/v1/kpis/measure_lineages", params: { predecessor_id: @measure_a.id }
    assert_response :success
    rows = JSON.parse(response.body)["data"]
    assert_equal 1, rows.length
    assert_equal @measure_a.id, rows.first["predecessor"]["id"]
    assert_equal "methodology_revision", rows.first["transition_kind"]
  end
end
