require "test_helper"

class Warehouse::ExtractedObservationTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "EO-#{SecureRandom.hex(2)}") do |j|
      j.name = "EO Test"; j.slug = "eo-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "eo-org-#{SecureRandom.hex(2)}", canonical_name: "EO Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/eo-#{SecureRandom.hex(4)}.pdf", published_at: Date.new(2024, 3, 1))
    @measure = Warehouse::Measure.create!(organization: @org, slug: "eo-m-#{SecureRandom.hex(2)}",
      canonical_name: "EO Measure", unit: @unit)
  end

  test "review_status defaults to pending and needs_review defaults to false" do
    o = Warehouse::ExtractedObservation.create!(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 1
    )
    assert_equal "pending", o.review_status
    assert_equal false, o.needs_review
    refute o.approved?
  end

  test "rejects invalid review_status" do
    o = Warehouse::ExtractedObservation.new(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 1, review_status: "bogus"
    )
    refute o.valid?
    assert_includes o.errors[:review_status], "is not included in the list"
  end

  test "rejects extraction_confidence outside [0,1]" do
    o = Warehouse::ExtractedObservation.new(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 1, extraction_confidence: 1.5
    )
    refute o.valid?
    refute_empty o.errors[:extraction_confidence]
  end

  test "promote_to_canonical! creates a canonical_observation and flips review_status" do
    o = Warehouse::ExtractedObservation.create!(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 42, observed_organization: @org,
      jurisdiction: @jur, extraction_confidence: 0.95
    )

    assert_difference -> { Warehouse::CanonicalObservation.count } => 1 do
      o.promote_to_canonical!(approved_by: "alice")
    end

    o.reload
    assert_equal "approved", o.review_status
    refute o.needs_review

    canonical = o.canonical_observation
    assert_equal @measure.id, canonical.measure_id
    assert_equal @org.id,    canonical.observed_organization_id
    assert_equal @jur.id,    canonical.jurisdiction_id
    assert_equal @unit.id,   canonical.unit_id
    assert_equal "alice",    canonical.approved_by
    assert_equal Date.new(2024, 3, 1), canonical.vintage_date.to_date
    assert_equal 42.0,       canonical.value_numeric
    assert_equal "reported", canonical.status
  end

  test "promote_to_canonical! is idempotent" do
    o = Warehouse::ExtractedObservation.create!(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 7
    )
    o.promote_to_canonical!(approved_by: "alice")
    assert_no_difference -> { Warehouse::CanonicalObservation.count } do
      o.promote_to_canonical!(approved_by: "bob")
    end
  end

  test "promote_to_canonical! falls back to measure.organization_id when observed_organization is unset" do
    o = Warehouse::ExtractedObservation.create!(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 9
    )
    o.promote_to_canonical!(approved_by: "alice")
    assert_equal @org.id, o.canonical_observation.observed_organization_id
  end

  test "measure_facts view reads from canonical_observations only" do
    o = Warehouse::ExtractedObservation.create!(
      measure: @measure, document: @doc, measurement_year: 2024,
      value_type: "actual", value_numeric: 50
    )
    assert_equal 0, Warehouse::MeasureFact.where(measure_id: @measure.id).count

    o.promote_to_canonical!(approved_by: "alice")
    facts = Warehouse::MeasureFact.where(measure_id: @measure.id).to_a
    assert_equal 1, facts.size
    assert_equal 50.0, facts.first.value_numeric
    assert_equal o.canonical_observation.id, facts.first.canonical_observation_id
  end

  test "scopes filter by review_status" do
    pending  = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)
    approved = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "target", value_numeric: 2)
    approved.promote_to_canonical!(approved_by: "x")

    assert_includes Warehouse::ExtractedObservation.pending.to_a, pending
    refute_includes Warehouse::ExtractedObservation.pending.to_a, approved
    assert_includes Warehouse::ExtractedObservation.approved.to_a, approved
  end
end
