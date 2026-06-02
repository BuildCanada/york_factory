require "test_helper"

class Api::V1::Kpis::Admin::ReviewWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "RVW-#{SecureRandom.hex(2)}") do |j|
      j.name = "Rvw"; j.slug = "rvw-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "rvw-#{SecureRandom.hex(2)}", canonical_name: "Rvw Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/rvw-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "rvw-m-#{SecureRandom.hex(2)}",
      canonical_name: "Rvw Measure", unit: @unit)
    @raw_token = Warehouse::ApiToken.issue!(name: "rvw-#{SecureRandom.hex(2)}", scopes: [ "kpis:write" ])
  end

  test "POST flag/approve/reject + GET review_queue end-to-end" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 10)

    # Create a flag → observation surfaces in queue.
    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/review_flags",
      params: { flag_type: "low_confidence_extraction", severity: "high",
                message: "OCR garbled the unit" },
      headers: auth_headers
    assert_response :created
    flag_id = JSON.parse(response.body)["id"]

    get "/api/v1/kpis/admin/review_queue", headers: auth_headers
    assert_response :success
    queue = JSON.parse(response.body)["data"]
    queue_ids = queue.map { |r| r["extracted_observation_id"] }
    assert_includes queue_ids, obs.id
    row = queue.find { |r| r["extracted_observation_id"] == obs.id }
    assert_equal "high", row["highest_open_severity"]
    assert_equal 1, row["open_flag_count"]

    # Resolve the flag.
    patch "/api/v1/kpis/admin/extracted_observations/#{obs.id}/review_flags/#{flag_id}",
      params: { resolved_by: "alice", resolution_notes: "verified" },
      headers: auth_headers
    assert_response :success

    # Approve.
    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/approve",
      params: { reviewer: "alice", notes: "ok" },
      headers: auth_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "approved", body["review_status"]
    assert body["canonical_observation_id"]
    assert_equal 0, body["open_flag_count"]

    # Observation falls out of queue post-approval.
    get "/api/v1/kpis/admin/review_queue", headers: auth_headers
    queue_ids = JSON.parse(response.body)["data"].map { |r| r["extracted_observation_id"] }
    refute_includes queue_ids, obs.id
  end

  test "reject endpoint records a rejected decision and creates no canonical row" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "target", value_numeric: 5)

    assert_no_difference -> { Warehouse::CanonicalObservation.count } do
      post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/reject",
        params: { reviewer: "bob", notes: "wrong measure" },
        headers: auth_headers
    end
    assert_response :success
    assert_equal "rejected", JSON.parse(response.body)["review_status"]
  end

  test "approve with new_value applies edits and records edited decision" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 100)

    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/approve",
      params: { reviewer: "alice", new_value: { value_numeric: 250 } },
      headers: auth_headers
    assert_response :success
    assert_equal 250.0, obs.reload.value_numeric
    assert_equal "edited", obs.review_decisions.last.decision
  end

  test "review_queue filters by min_severity" do
    crit = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1, needs_review: true)
    low  = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "target", value_numeric: 1, needs_review: true)
    crit.review_flags.create!(flag_type: "x", severity: "critical", message: "m")
    low.review_flags.create!(flag_type: "x", severity: "low",      message: "m")

    get "/api/v1/kpis/admin/review_queue", params: { min_severity: "high" }, headers: auth_headers
    ids = JSON.parse(response.body)["data"].map { |r| r["extracted_observation_id"] }
    assert_includes ids, crit.id
    refute_includes ids, low.id
  end

  test "review_flags endpoint rejects missing fields" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)
    post "/api/v1/kpis/admin/extracted_observations/#{obs.id}/review_flags",
      params: { severity: "high" }, headers: auth_headers
    assert_response :unprocessable_entity
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@raw_token}" }
  end
end
