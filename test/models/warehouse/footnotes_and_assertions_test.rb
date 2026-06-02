require "test_helper"

class Warehouse::FootnotesAndAssertionsTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "FN-#{SecureRandom.hex(2)}") do |j|
      j.name = "FN"; j.slug = "fn-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "fn-#{SecureRandom.hex(2)}", canonical_name: "FN Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/fn-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "fn-m-#{SecureRandom.hex(2)}",
      canonical_name: "FN Measure", unit: @unit)
    @obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)
  end

  test "footnote requires text" do
    footnote = @doc.source_footnotes.build
    refute footnote.valid?
    assert_includes footnote.errors[:footnote_text], "can't be blank"
  end

  test "linking same footnote twice is idempotent" do
    footnote = @doc.source_footnotes.create!(footnote_text: "no more than 5 min late", marker: "1")
    Warehouse::ObservationFootnote.find_or_create_by!(extracted_observation_id: @obs.id, source_footnote_id: footnote.id)
    Warehouse::ObservationFootnote.find_or_create_by!(extracted_observation_id: @obs.id, source_footnote_id: footnote.id)
    assert_equal 1, @obs.source_footnotes.count
  end

  test "destroying document cascades footnotes" do
    @doc.source_footnotes.create!(footnote_text: "fn")
    assert_difference -> { Warehouse::SourceFootnote.count } => -1 do
      # Avoid restrict_with_error on observations: destroy observation first.
      @obs.destroy
      @doc.destroy
    end
  end

  test "extraction_assertion confidence bounds enforced" do
    assertion = @obs.extraction_assertions.build(
      assertion_type: "unit", assertion_text: "value is in thousands", confidence: 1.5
    )
    refute assertion.valid?
    refute_empty assertion.errors[:confidence]
  end

  test "extraction_assertion stores reasoning + evidence" do
    a = @obs.extraction_assertions.create!(
      assertion_type: "unit",
      assertion_text: "value is in thousands of dollars",
      confidence: 0.92,
      evidence_quote: "Table notes: amounts shown in $000s.",
      source_page: 12
    )
    assert_equal 12, a.source_page
    assert_equal "unit", a.assertion_type
  end
end
