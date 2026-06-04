require "test_helper"

class Warehouse::CanonicalObservationTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "CO-#{SecureRandom.hex(2)}") do |j|
      j.name = "CO Test"; j.slug = "co-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "co-org-#{SecureRandom.hex(2)}", canonical_name: "CO Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/co-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "co-m-#{SecureRandom.hex(2)}",
      canonical_name: "CO Measure", unit: @unit)
  end

  test "rejects invalid status" do
    o = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)
    canonical = Warehouse::CanonicalObservation.new(extracted_observation: o, measure: @measure,
      document: @doc, measurement_year: 2024, value_type: "actual", period_basis: "full_year",
      status: "bogus")
    refute canonical.valid?
    assert_includes canonical.errors[:status], "is not included in the list"
  end

  test "is unique on extracted_observation_id" do
    o = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)
    o.promote_to_canonical!(approved_by: "x")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Warehouse::CanonicalObservation.create!(
        extracted_observation: o, measure: @measure, document: @doc,
        measurement_year: 2024, value_type: "actual", period_basis: "full_year"
      )
    end
  end
end
