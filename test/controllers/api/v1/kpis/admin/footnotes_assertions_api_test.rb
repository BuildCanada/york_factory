require "test_helper"

class Api::V1::Kpis::Admin::FootnotesAssertionsApiTest < ActionDispatch::IntegrationTest
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "FA-#{SecureRandom.hex(2)}") do |j|
      j.name = "FA"; j.slug = "fa-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "fa-#{SecureRandom.hex(2)}", canonical_name: "FA Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/fa-#{SecureRandom.hex(4)}.pdf")
    @other_doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/fa-other-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "fa-m-#{SecureRandom.hex(2)}",
      canonical_name: "FA Measure", unit: @unit)
    @obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)
    @raw_token = Warehouse::ApiToken.issue!(name: "fa-#{SecureRandom.hex(2)}", scopes: [ "kpis:write" ])
  end

  test "creates a footnote on a document" do
    post "/api/v1/kpis/admin/documents/#{@doc.id}/footnotes",
      params: { footnote_text: "amounts in $000s", page: 12, marker: "1" },
      headers: auth_headers
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal @doc.id, body["document_id"]
    assert_equal "1", body["marker"]
  end

  test "creates an extraction assertion" do
    post "/api/v1/kpis/admin/extracted_observations/#{@obs.id}/assertions",
      params: { assertion_type: "unit", assertion_text: "value is in thousands", confidence: 0.92 },
      headers: auth_headers
    assert_response :created
    assert_equal "unit", JSON.parse(response.body)["assertion_type"]
  end

  test "links a footnote to an observation in the same document" do
    footnote = @doc.source_footnotes.create!(footnote_text: "fn", marker: "1")
    post "/api/v1/kpis/admin/extracted_observations/#{@obs.id}/footnote_links",
      params: { source_footnote_id: footnote.id },
      headers: auth_headers
    assert_response :created
    assert_equal 1, @obs.source_footnotes.count
  end

  test "rejects cross-document footnote link" do
    foreign_footnote = @other_doc.source_footnotes.create!(footnote_text: "fn")
    post "/api/v1/kpis/admin/extracted_observations/#{@obs.id}/footnote_links",
      params: { source_footnote_id: foreign_footnote.id },
      headers: auth_headers
    assert_response :unprocessable_entity
    assert_equal "footnote_document_mismatch", JSON.parse(response.body)["error"]
  end

  test "deletes a footnote link" do
    footnote = @doc.source_footnotes.create!(footnote_text: "fn")
    Warehouse::ObservationFootnote.create!(extracted_observation: @obs, source_footnote: footnote)
    delete "/api/v1/kpis/admin/extracted_observations/#{@obs.id}/footnote_links/#{footnote.id}",
      headers: auth_headers
    assert_response :no_content
    assert_equal 0, @obs.source_footnotes.count
  end

  test "links a footnote to a measure and surfaces it on measure show" do
    footnote = @doc.source_footnotes.create!(footnote_text: "Indicator retired; data collection ended.", marker: "c")
    post "/api/v1/kpis/admin/measures/#{@measure.id}/footnote_links",
      params: { source_footnote_id: footnote.id },
      headers: auth_headers
    assert_response :created
    assert_equal 1, @measure.source_footnotes.count

    # Idempotent.
    post "/api/v1/kpis/admin/measures/#{@measure.id}/footnote_links",
      params: { source_footnote_id: footnote.id },
      headers: auth_headers
    assert_response :created
    assert_equal 1, @measure.source_footnotes.count

    get "/api/v1/kpis/measures/#{@measure.id}"
    assert_response :success
    fn = JSON.parse(response.body)["footnotes"].sole
    assert_equal "Indicator retired; data collection ended.", fn["footnote_text"]
    assert_equal @doc.id, fn["document_id"]
  end

  test "deletes a measure footnote link" do
    footnote = @doc.source_footnotes.create!(footnote_text: "fn")
    Warehouse::MeasureFootnote.create!(measure: @measure, source_footnote: footnote)
    delete "/api/v1/kpis/admin/measures/#{@measure.id}/footnote_links/#{footnote.id}",
      headers: auth_headers
    assert_response :no_content
    assert_equal 0, @measure.source_footnotes.count
  end

  test "citations index serializes measure and linked footnotes" do
    footnote = @doc.source_footnotes.create!(footnote_text: "Data source changed in 2024.", marker: "f")
    Warehouse::ObservationFootnote.create!(extracted_observation: @obs, source_footnote: footnote)

    get "/api/v1/kpis/citations", params: { document_id: @doc.id }
    assert_response :success
    row = JSON.parse(response.body)["data"].find { |c| c["id"] == @obs.id }
    assert_equal @measure.slug, row["measure"]["slug"]
    fn = row["footnotes"].sole
    assert_equal "Data source changed in 2024.", fn["footnote_text"]
    assert_equal "f", fn["marker"]
  end

  test "review queue serializes linked footnotes" do
    footnote = @doc.source_footnotes.create!(footnote_text: "Comparability caveat.", marker: "b")
    Warehouse::ObservationFootnote.create!(extracted_observation: @obs, source_footnote: footnote)
    @obs.update!(needs_review: true)

    get "/api/v1/kpis/admin/review_queue", params: { document_id: @doc.id }, headers: auth_headers
    assert_response :success
    row = JSON.parse(response.body)["data"].find { |r| r["extracted_observation_id"] == @obs.id }
    assert_equal "Comparability caveat.", row["footnotes"].sole["footnote_text"]
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@raw_token}" }
  end
end
