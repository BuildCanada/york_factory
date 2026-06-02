require "test_helper"

class Warehouse::ObservationReviewFlagTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "RF-#{SecureRandom.hex(2)}") do |j|
      j.name = "RF"; j.slug = "rf-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "rf-org-#{SecureRandom.hex(2)}", canonical_name: "RF Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/rf-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "rf-m-#{SecureRandom.hex(2)}",
      canonical_name: "RF Measure", unit: @unit)
    @obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1)
  end

  test "rejects invalid severity" do
    flag = @obs.review_flags.build(flag_type: "low_confidence", severity: "yikes", message: "m")
    refute flag.valid?
  end

  test "requires flag_type and message" do
    flag = @obs.review_flags.build
    refute flag.valid?
    assert_includes flag.errors[:flag_type], "can't be blank"
    assert_includes flag.errors[:message],   "can't be blank"
  end

  test "resolve! sets resolved_at + resolved_by together" do
    flag = @obs.review_flags.create!(flag_type: "x", severity: "low", message: "m")
    assert flag.open?
    flag.resolve!(resolved_by: "alice", notes: "ok")
    refute flag.open?
    assert_equal "alice", flag.resolved_by
    assert_equal "ok",    flag.resolution_notes
  end

  test "can't set resolved_at without resolved_by" do
    flag = @obs.review_flags.create!(flag_type: "x", severity: "low", message: "m")
    flag.resolved_at = Time.current
    refute flag.valid?
  end
end
