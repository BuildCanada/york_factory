require "test_helper"

class Warehouse::AlertsTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "AL-#{SecureRandom.hex(2)}") do |j|
      j.name = "AL"; j.slug = "al-#{SecureRandom.hex(2)}"
      j.level = "provincial"; j.fiscal_year_start_month = 4; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "al-#{SecureRandom.hex(2)}", canonical_name: "AL Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/al-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "al-m-#{SecureRandom.hex(2)}",
      canonical_name: "Debt", unit: @unit, aggregation_type: "additive")
  end

  def canonical!(year:, value:, approved_at: nil)
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: year, value_type: "actual", value_numeric: value,
      observed_organization: @org)
    obs.approve!(reviewer: "x")
    obs.canonical_observation.tap { |c| c.update!(approved_at: approved_at) if approved_at }
  end

  test "above condition fires when latest value exceeds threshold" do
    canonical!(year: 2024, value: 200)
    alert = Warehouse::Alert.create!(name: "Big debt", measure: @measure, observed_organization: @org,
      condition_type: "above", threshold_value: 150, severity: "high")
    assert event = alert.evaluate!
    assert_equal 200.0, event.observed_value
    assert_equal 150.0, event.comparison_value
  end

  test "above condition no-op when value under threshold" do
    canonical!(year: 2024, value: 100)
    alert = Warehouse::Alert.create!(name: "Big debt", measure: @measure, observed_organization: @org,
      condition_type: "above", threshold_value: 150)
    assert_nil alert.evaluate!
  end

  test "percent_change fires only when |Δ%| exceeds threshold" do
    canonical!(year: 2023, value: 100)
    canonical!(year: 2024, value: 120)
    alert = Warehouse::Alert.create!(name: "Big jump", measure: @measure, observed_organization: @org,
      condition_type: "percent_change", threshold_value: 15)
    assert event = alert.evaluate!
    assert_includes event.message, "percent change"

    quiet = Warehouse::Alert.create!(name: "Quiet jump", measure: @measure, observed_organization: @org,
      condition_type: "percent_change", threshold_value: 25)
    assert_nil quiet.evaluate!
  end

  test "absolute_change fires when |Δ| exceeds threshold" do
    canonical!(year: 2023, value: 100)
    canonical!(year: 2024, value: 130)
    alert = Warehouse::Alert.create!(name: "Big absolute jump", measure: @measure, observed_organization: @org,
      condition_type: "absolute_change", threshold_value: 20)
    assert event = alert.evaluate!
    assert_includes event.message, "absolute change"
  end

  test "missing_update fires when latest approval is older than threshold days" do
    old = canonical!(year: 2024, value: 100, approved_at: 60.days.ago)
    alert = Warehouse::Alert.create!(name: "Stale", measure: @measure, observed_organization: @org,
      condition_type: "missing_update", threshold_value: 30)
    assert event = alert.evaluate!
    assert_equal old.id, event.canonical_observation_id
  end

  test "missing_update no-op when recent approval exists" do
    canonical!(year: 2024, value: 100) # default approved_at = now
    alert = Warehouse::Alert.create!(name: "Stale", measure: @measure, observed_organization: @org,
      condition_type: "missing_update", threshold_value: 30)
    assert_nil alert.evaluate!
  end

  test "disabled alert evaluates to nil" do
    canonical!(year: 2024, value: 200)
    alert = Warehouse::Alert.create!(name: "Big debt", measure: @measure, observed_organization: @org,
      condition_type: "above", threshold_value: 150, enabled: false)
    assert_nil alert.evaluate!
  end

  test "rejects invalid condition_type and severity" do
    a = Warehouse::Alert.new(name: "x", condition_type: "bogus", severity: "low")
    refute a.valid?
    b = Warehouse::Alert.new(name: "x", condition_type: "above", severity: "lalala")
    refute b.valid?
  end
end
