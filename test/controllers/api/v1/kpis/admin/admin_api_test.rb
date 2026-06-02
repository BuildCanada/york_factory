require "test_helper"

class Api::V1::Kpis::Admin::AdminApiTest < ActionDispatch::IntegrationTest
  setup do
    @jurisdiction = Warehouse::Jurisdiction.find_or_create_by!(code: "TOR-ON") do |j|
      j.name = "City of Toronto"
      j.slug = "toronto"
      j.level = "municipal"
      j.fiscal_year_start_month = 1
      j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.find_or_create_by!(jurisdiction_id: @jurisdiction.id, slug: "admin-test-org-#{SecureRandom.hex(2)}") do |o|
      o.canonical_name = "Admin Test Org #{SecureRandom.hex(2)}"
    end
    @raw_token = Warehouse::ApiToken.issue!(name: "admin-test-#{SecureRandom.hex(2)}", scopes: [ "kpis:write" ])
  end

  test "rejects requests without bearer token" do
    post "/api/v1/kpis/admin/documents", params: { document: { jurisdiction_slug: "toronto", fiscal_year: 2024, doc_url: "x" } }
    assert_response :unauthorized
  end

  test "rejects tokens without kpis:write scope" do
    raw = Warehouse::ApiToken.issue!(name: "read-only-#{SecureRandom.hex(2)}", scopes: [ "kpis:read" ])
    post "/api/v1/kpis/admin/documents",
      params: { document: { jurisdiction_slug: "toronto", fiscal_year: 2024, doc_url: "y" } },
      headers: { "Authorization" => "Bearer #{raw}" }
    assert_response :forbidden
  end

  test "creates and upserts a document idempotently" do
    url = "https://example.com/admin-doc-#{SecureRandom.hex(4)}.pdf"
    payload = { document: {
      jurisdiction_slug: "toronto",
      organization_slug: @org.slug,
      fiscal_year: 2027,
      doc_url: url,
      doc_title: "First title"
    } }

    post "/api/v1/kpis/admin/documents", params: payload, headers: auth_headers
    assert_response :success
    first_id = JSON.parse(response.body)["id"]

    # Repost with updated title; should not create a new row.
    payload[:document][:doc_title] = "Second title"
    post "/api/v1/kpis/admin/documents", params: payload, headers: auth_headers
    assert_response :success
    assert_equal first_id, JSON.parse(response.body)["id"]
    assert_equal "Second title", Warehouse::KpiDocument.find(first_id).doc_title
  end

  test "bulk citations: inserts new and skips duplicates" do
    doc = Warehouse::KpiDocument.create!(jurisdiction: @jurisdiction, organization: @org,
      fiscal_year: 2027, doc_url: "https://example.com/bulk-#{SecureRandom.hex(4)}.pdf")
    measure = Warehouse::Measure.create!(organization: @org, slug: "bulk-test-#{SecureRandom.hex(2)}",
      canonical_name: "Bulk Test", unit: @unit)

    rows = [
      { measure_id: measure.id, measurement_year: 2024, value_type: "actual", value_numeric: 100, document_id: doc.id },
      { measure_id: measure.id, measurement_year: 2025, value_type: "actual", value_numeric: 200, document_id: doc.id },
      { measure_id: measure.id, measurement_year: 2024, value_type: "actual", value_numeric: 100, document_id: doc.id } # dup
    ]
    post "/api/v1/kpis/admin/citations", params: { citations: rows }, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["inserted"]
    assert_equal 1, body["skipped_duplicate"]
  end

  test "agent_run_id stamps documents, measures, and citations when provided" do
    run = Warehouse::AgentRun.create!(agent_name: "stamp-test", status: "running", started_at: Time.current)

    url = "https://example.com/stamp-#{SecureRandom.hex(4)}.pdf"
    post "/api/v1/kpis/admin/documents",
      params: { document: { jurisdiction_slug: "toronto", organization_slug: @org.slug,
                            fiscal_year: 2099, doc_url: url, agent_run_id: run.id } },
      headers: auth_headers
    doc_id = JSON.parse(response.body)["id"]
    assert_equal run.id, Warehouse::KpiDocument.find(doc_id).agent_run_id

    post "/api/v1/kpis/admin/measures",
      params: { measure: { organization_slug: @org.slug, slug: "stamp-m-#{SecureRandom.hex(2)}",
                           canonical_name: "Stamp M", unit_symbol: "count", agent_run_id: run.id } },
      headers: auth_headers
    measure_id = JSON.parse(response.body)["id"]
    assert_equal run.id, Warehouse::Measure.find(measure_id).agent_run_id

    post "/api/v1/kpis/admin/citations",
      params: { agent_run_id: run.id, citations: [
        { measure_id: measure_id, measurement_year: 2024, value_type: "actual", value_numeric: 1, document_id: doc_id }
      ] },
      headers: auth_headers
    citation_id = JSON.parse(response.body)["ids"].first
    assert_equal run.id, Warehouse::ExtractedObservation.find(citation_id).agent_run_id
  end

  test "bulk citations: inline review_flags create flags and mark needs_review" do
    doc = Warehouse::KpiDocument.create!(jurisdiction: @jurisdiction, organization: @org,
      fiscal_year: 2027, doc_url: "https://example.com/flags-#{SecureRandom.hex(4)}.pdf")
    measure = Warehouse::Measure.create!(organization: @org, slug: "flags-test-#{SecureRandom.hex(2)}",
      canonical_name: "Flags Test", unit: @unit)

    # First request inserts the 2024 row so it is a duplicate in the second
    # request — flags must still land on the right observation.
    post "/api/v1/kpis/admin/citations", params: { citations: [
      { measure_id: measure.id, measurement_year: 2024, value_type: "actual", value_numeric: 100, document_id: doc.id }
    ] }, headers: auth_headers
    assert_response :success

    rows = [
      { measure_id: measure.id, measurement_year: 2024, value_type: "actual", value_numeric: 100, document_id: doc.id }, # dup
      { measure_id: measure.id, measurement_year: 2025, value_type: "actual", value_numeric: 200, document_id: doc.id,
        review_flags: [ { flag_type: "unit_ambiguous", severity: "high", message: "Header could mean millions or billions" } ] },
      { measure_id: measure.id, measurement_year: 2026, value_type: "actual", value_numeric: 300, document_id: doc.id }
    ]
    post "/api/v1/kpis/admin/citations", params: { citations: rows }, headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["inserted"]
    assert_equal 1, body["skipped_duplicate"]

    flagged = Warehouse::ExtractedObservation.find_by!(measure_id: measure.id, measurement_year: 2025, document_id: doc.id)
    assert flagged.needs_review
    flag = flagged.review_flags.sole
    assert_equal "unit_ambiguous", flag.flag_type
    assert_equal "high", flag.severity

    unflagged = Warehouse::ExtractedObservation.find_by!(measure_id: measure.id, measurement_year: 2026, document_id: doc.id)
    assert_not unflagged.needs_review
    assert_empty unflagged.review_flags
  end

  test "unit create adds a new unit and returns existing ones untouched" do
    symbol = "test-unit-#{SecureRandom.hex(2)}"
    post "/api/v1/kpis/admin/units",
      params: { unit: { symbol: symbol, kind: "absolute", base_unit: "count", scale: 1.0 } },
      headers: auth_headers
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal symbol, body["symbol"]
    assert_equal false, body["existing"]

    # Reposting the same symbol with different attributes must not overwrite.
    post "/api/v1/kpis/admin/units",
      params: { unit: { symbol: symbol, kind: "absolute", base_unit: "dollars", scale: 1000.0 } },
      headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["existing"]
    assert_equal "count", Warehouse::Unit.find_by!(symbol: symbol).base_unit
  end

  test "units index lists the catalog" do
    get "/api/v1/kpis/units"
    assert_response :success
    symbols = JSON.parse(response.body)["data"].map { |u| u["symbol"] }
    assert_includes symbols, "count"
  end

  test "measure create rejects unknown unit symbol" do
    post "/api/v1/kpis/admin/measures",
      params: { measure: { organization_slug: @org.slug, slug: "nope-#{SecureRandom.hex(2)}", canonical_name: "Nope", unit_symbol: "fake-unit" } },
      headers: auth_headers
    assert_response :unprocessable_entity
    assert_equal "unknown_unit", JSON.parse(response.body)["error"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@raw_token}" }
  end
end
