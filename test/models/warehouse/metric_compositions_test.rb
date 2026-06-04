require "test_helper"

class Warehouse::MetricCompositionsTest < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "MC-#{SecureRandom.hex(2)}") do |j|
      j.name = "MC"; j.slug = "mc-#{SecureRandom.hex(2)}"
      j.level = "provincial"; j.fiscal_year_start_month = 4; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "CAD") { |u| u.kind = "absolute"; u.base_unit = "dollars"; u.scale = 1.0; u.currency_code = "CAD" }
    @pct  = Warehouse::Unit.find_or_create_by!(symbol: "percent") { |u| u.kind = "ratio"; u.base_unit = "ratio"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "mc-#{SecureRandom.hex(2)}", canonical_name: "MC Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2025,
      doc_url: "https://example.com/mc-#{SecureRandom.hex(4)}.pdf")
    @revenue = Warehouse::Measure.create!(organization: @org, slug: "revenue-#{SecureRandom.hex(2)}",
      canonical_name: "Revenue", unit: @unit, aggregation_type: "additive")
    @currency_exposure = Warehouse::Measure.create!(organization: @org, slug: "currency-exposure-#{SecureRandom.hex(2)}",
      canonical_name: "Currency exposure", unit: @pct, aggregation_type: "part_of_whole")
  end

  test "metric_composition is unique by (measure_id, composition_type)" do
    @revenue.metric_versions.create!(version_label: "v1", definition: "x")
    a = Warehouse::MetricComposition.create!(measure: @revenue, composition_type: "by_source", name: "Revenue by source")
    dup = Warehouse::MetricComposition.new(measure: @revenue, composition_type: "by_source", name: "Dup")
    refute dup.valid?
    assert a.persisted?
  end

  test "components nest with parent_component_id" do
    comp = Warehouse::MetricComposition.create!(measure: @revenue, composition_type: "by_source", name: "By source")
    tax = Warehouse::MetricComponent.create!(measure: @revenue, composition: comp,
      component_type: "revenue_source", component_code: "tax", component_name: "Tax revenue")
    property = Warehouse::MetricComponent.create!(measure: @revenue, composition: comp,
      component_type: "revenue_source", component_code: "property_tax",
      component_name: "Property tax", parent_component: tax)
    assert_includes tax.child_components, property
    assert_equal tax, property.parent_component
  end

  test "metric_component_relationship requires distinct components" do
    comp = Warehouse::MetricComposition.create!(measure: @revenue, composition_type: "by_source", name: "x")
    a = Warehouse::MetricComponent.create!(measure: @revenue, composition: comp,
      component_type: "rs", component_code: "a", component_name: "A")
    rel = Warehouse::MetricComponentRelationship.new(from_component: a, to_component: a,
      relationship_type: "renamed_to")
    refute rel.valid?
  end

  test "validator flags components_sum_to_100 when they don't" do
    composition = Warehouse::MetricComposition.create!(
      measure: @currency_exposure, composition_type: "by_currency", name: "By currency",
      expected_total: 100, expected_total_unit: @pct
    )
    cad = Warehouse::MetricComponent.create!(measure: @currency_exposure, composition: composition,
      component_type: "currency", component_code: "CAD", component_name: "Canadian Dollar")
    cny = Warehouse::MetricComponent.create!(measure: @currency_exposure, composition: composition,
      component_type: "currency", component_code: "CNY", component_name: "Chinese Renminbi")

    [ [ cad, 23 ], [ cny, 4 ] ].each do |comp, val|
      obs = Warehouse::ExtractedObservation.create!(measure: @currency_exposure, document: @doc,
        measurement_year: 2025, value_type: "actual", value_numeric: val,
        composition: composition, component: comp, observed_organization: @org)
      obs.approve!(reviewer: "x")
    end

    results = Warehouse::MetricComposition::Validator.run!(
      composition: composition, measurement_year: 2025, observed_organization: @org
    )
    sum_check = results.find { |r| r.validation_type == "components_sum_to_100" }
    assert_equal "fail", sum_check.status
    assert_equal 27.0, sum_check.actual_value
    assert_equal 100.0, sum_check.expected_value
    assert_equal -73.0, sum_check.difference
    assert_equal "critical", sum_check.severity
  end

  test "validator flags components_sum_to_total against the is_total row" do
    composition = Warehouse::MetricComposition.create!(measure: @revenue, composition_type: "by_source", name: "By source")
    tax = Warehouse::MetricComponent.create!(measure: @revenue, composition: composition,
      component_type: "revenue_source", component_code: "tax", component_name: "Tax")
    fees = Warehouse::MetricComponent.create!(measure: @revenue, composition: composition,
      component_type: "revenue_source", component_code: "fees", component_name: "Fees")

    [
      { component: tax,  value: 80, is_total: false },
      { component: fees, value: 15, is_total: false },
      { component: nil,  value: 100, is_total: true } # 95 != 100 → flag
    ].each do |row|
      obs = Warehouse::ExtractedObservation.create!(measure: @revenue, document: @doc,
        measurement_year: 2025, value_type: "actual",
        value_numeric: row[:value], composition: composition, component: row[:component],
        observed_organization: @org)
      obs.approve!(reviewer: "x", is_total: row[:is_total])
    end

    results = Warehouse::MetricComposition::Validator.run!(
      composition: composition, measurement_year: 2025, observed_organization: @org
    )
    total_check = results.find { |r| r.validation_type == "components_sum_to_total" }
    assert_equal "fail", total_check.status
    assert_equal 95.0,  total_check.actual_value
    assert_equal 100.0, total_check.expected_value
  end

  test "validator returns ok when sums match within tolerance" do
    composition = Warehouse::MetricComposition.create!(measure: @currency_exposure, composition_type: "by_currency",
      name: "By currency", expected_total: 100, expected_total_unit: @pct)
    cad = Warehouse::MetricComponent.create!(measure: @currency_exposure, composition: composition,
      component_type: "currency", component_code: "CAD", component_name: "CAD")
    eur = Warehouse::MetricComponent.create!(measure: @currency_exposure, composition: composition,
      component_type: "currency", component_code: "EUR", component_name: "EUR")
    [ [ cad, 60 ], [ eur, 40 ] ].each do |comp, val|
      obs = Warehouse::ExtractedObservation.create!(measure: @currency_exposure, document: @doc,
        measurement_year: 2025, value_type: "actual", value_numeric: val,
        composition: composition, component: comp, observed_organization: @org)
      obs.approve!(reviewer: "x")
    end

    results = Warehouse::MetricComposition::Validator.run!(
      composition: composition, measurement_year: 2025, observed_organization: @org
    )
    sum_check = results.find { |r| r.validation_type == "components_sum_to_100" }
    assert_equal "ok", sum_check.status
    assert_nil sum_check.severity
  end
end
