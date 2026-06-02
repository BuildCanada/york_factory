require "test_helper"

class Warehouse::MetricVersionsAndAliasesTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "MV-#{SecureRandom.hex(2)}") do |j|
      j.name = "MV"; j.slug = "mv-#{SecureRandom.hex(2)}"
      j.level = "municipal"; j.fiscal_year_start_month = 1; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org_a = Warehouse::Organization.create!(jurisdiction: @jur, slug: "mv-a-#{SecureRandom.hex(2)}", canonical_name: "MV Org A")
    @org_b = Warehouse::Organization.create!(jurisdiction: @jur, slug: "mv-b-#{SecureRandom.hex(2)}", canonical_name: "MV Org B")
    @measure_a = Warehouse::Measure.create!(organization: @org_a, slug: "total-debt", canonical_name: "Total debt", unit: @unit)
    @measure_b = Warehouse::Measure.create!(organization: @org_b, slug: "total-debt", canonical_name: "Total debt", unit: @unit)
    @canonical = Warehouse::Measure.create!(organization: nil, slug: "total-debt", canonical_name: "Total debt (canonical)", unit: @unit)
  end

  test "aggregation_type defaults to unknown for new measures" do
    m = Warehouse::Measure.create!(organization: @org_a, slug: "x-#{SecureRandom.hex(2)}",
      canonical_name: "X", unit: @unit)
    assert_equal "unknown", m.aggregation_type
  end

  test "rejects invalid aggregation_type" do
    m = Warehouse::Measure.new(organization: @org_a, slug: "x-#{SecureRandom.hex(2)}",
      canonical_name: "X", unit: @unit, aggregation_type: "bogus")
    refute m.valid?
    assert_includes m.errors[:aggregation_type], "is not included in the list"
  end

  test "ratio measure with components is accepted" do
    debt = Warehouse::Measure.create!(organization: @org_a, slug: "debt-#{SecureRandom.hex(2)}", canonical_name: "Debt", unit: @unit)
    pop  = Warehouse::Measure.create!(organization: @org_a, slug: "pop-#{SecureRandom.hex(2)}",  canonical_name: "Pop",  unit: @unit)
    rate = Warehouse::Measure.create!(organization: @org_a, slug: "rate-#{SecureRandom.hex(2)}", canonical_name: "Rate", unit: @unit,
      aggregation_type: "ratio", numerator_measure: debt, denominator_measure: pop)
    assert_equal "ratio", rate.aggregation_type
    assert_equal debt.id, rate.numerator_measure_id
    assert_equal pop.id,  rate.denominator_measure_id
  end

  test "ratio measure without components is rejected by DB constraint" do
    debt = Warehouse::Measure.create!(organization: @org_a, slug: "debt-#{SecureRandom.hex(2)}", canonical_name: "Debt", unit: @unit)
    assert_raises(ActiveRecord::StatementInvalid) do
      Warehouse::Measure.connection.execute(
        "UPDATE warehouse.measures SET aggregation_type = 'ratio' WHERE id = #{debt.id}"
      )
    end
  end

  test "metric_version enforces unique version_label per measure" do
    @measure_a.metric_versions.create!(version_label: "v1", definition: "first")
    duplicate = @measure_a.metric_versions.build(version_label: "v1", definition: "again")
    refute duplicate.valid?
  end

  test "metric_version active_to must be on/after active_from" do
    v = @measure_a.metric_versions.build(version_label: "x", definition: "y",
      active_from: Date.new(2024, 1, 1), active_to: Date.new(2023, 1, 1))
    refute v.valid?
  end

  test "metric_alias raw_text resolution finds the measure" do
    Warehouse::MetricAlias.create!(measure: @measure_a, alias_text: "Tax-supported debt", kind: "raw_text")
    assert_equal @measure_a, Warehouse::MetricAlias.resolve_raw_text("Tax-supported debt")
  end

  test "metric_alias measure_equivalence requires a canonical target distinct from measure" do
    self_target = Warehouse::MetricAlias.new(measure: @measure_a, kind: "measure_equivalence",
      alias_text: "Total debt", canonical_measure: @measure_a)
    refute self_target.valid?

    no_target = Warehouse::MetricAlias.new(measure: @measure_a, kind: "measure_equivalence",
      alias_text: "Total debt")
    refute no_target.valid?

    ok = Warehouse::MetricAlias.create!(measure: @measure_a, kind: "measure_equivalence",
      alias_text: "Total debt", canonical_measure: @canonical)
    assert ok.persisted?
  end

  test "measure.canonical_equivalent follows equivalence aliases for org-scoped measures" do
    Warehouse::MetricAlias.create!(measure: @measure_a, kind: "measure_equivalence",
      alias_text: "Total debt", canonical_measure: @canonical)
    assert_equal @canonical, @measure_a.reload.canonical_equivalent
    # Without alias, canonical_equivalent returns self.
    assert_equal @measure_b, @measure_b.reload.canonical_equivalent
    # A canonical measure returns itself.
    assert_equal @canonical, @canonical.canonical_equivalent
  end

  test "Measure::Resolver prefers alias over slug" do
    Warehouse::MetricAlias.create!(measure: @measure_a, alias_text: "TSD", kind: "raw_text")
    assert_equal @measure_a, Warehouse::Measure::Resolver.call("TSD", organization: @org_a)
  end

  test "Measure::Resolver falls back to canonical_name match" do
    assert_equal @measure_a, Warehouse::Measure::Resolver.call("Total debt", organization: @org_a)
  end

  test "Measure::Resolver falls back to slugified match" do
    assert_equal @measure_a, Warehouse::Measure::Resolver.call("total-debt", organization: @org_a)
  end

  test "promoting an observation carries metric_version_id forward" do
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org_a, fiscal_year: 2024,
      doc_url: "https://example.com/mv-#{SecureRandom.hex(4)}.pdf")
    version = @measure_a.metric_versions.create!(version_label: "v1", definition: "first")
    obs = Warehouse::ExtractedObservation.create!(measure: @measure_a, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 1, metric_version: version)
    obs.approve!(reviewer: "x")
    assert_equal version.id, obs.canonical_observation.metric_version_id
  end
end
