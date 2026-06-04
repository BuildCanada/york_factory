require "test_helper"

class Warehouse::CrosswalksV2Test < ActiveSupport::TestCase
  setup do
    @jur = Warehouse::Jurisdiction.find_or_create_by!(code: "CX-#{SecureRandom.hex(2)}") do |j|
      j.name = "CX"; j.slug = "cx-#{SecureRandom.hex(2)}"
      j.level = "provincial"; j.fiscal_year_start_month = 4; j.default_currency = "CAD"
    end
    @unit = Warehouse::Unit.find_or_create_by!(symbol: "count") { |u| u.kind = "absolute"; u.base_unit = "count"; u.scale = 1.0 }
    @org = Warehouse::Organization.create!(jurisdiction: @jur, slug: "cx-#{SecureRandom.hex(2)}", canonical_name: "CX Org")
    @doc = Warehouse::KpiDocument.create!(jurisdiction: @jur, organization: @org, fiscal_year: 2024,
      doc_url: "https://example.com/cx-#{SecureRandom.hex(4)}.pdf")
    @measure = Warehouse::Measure.create!(organization: @org, slug: "cx-m-#{SecureRandom.hex(2)}",
      canonical_name: "Population", unit: @unit, aggregation_type: "additive")
    @ratio_measure = Warehouse::Measure.create!(organization: @org, slug: "cx-r-#{SecureRandom.hex(2)}",
      canonical_name: "Unemployment rate", unit: @unit, aggregation_type: "non_aggregable")

    @geo_a = Warehouse::GeoBoundary.create!(name_en: "Source DA",
      boundary_type: "da",
      geo_uid: "DA-#{SecureRandom.hex(3)}",
      province_code: "ON", census_year: 2021, code_system: "da_2021")
    @geo_b = Warehouse::GeoBoundary.create!(name_en: "Target CSD",
      boundary_type: "csd",
      geo_uid: "CSD-#{SecureRandom.hex(3)}",
      province_code: "ON", census_year: 2021, code_system: "csd_2021")
    @geo_c = Warehouse::GeoBoundary.create!(name_en: "Target CSD 2",
      boundary_type: "csd",
      geo_uid: "CSD-#{SecureRandom.hex(3)}",
      province_code: "ON", census_year: 2021, code_system: "csd_2021")
  end

  test "geo_boundaries get code_system backfilled" do
    refute_nil @geo_a.code_system
    assert_includes @geo_a.code_system, "da"
  end

  test "crosswalk_set requires valid weight_basis" do
    set = Warehouse::GeographyCrosswalkSet.new(
      name: "x", method: "tabular", weight_basis: "wat",
      from_code_system: "a", to_code_system: "b"
    )
    refute set.valid?
  end

  test "crosswalk_entry weight is between 0 and 1" do
    set = Warehouse::GeographyCrosswalkSet.create!(
      name: "DA→CSD", method: "tabular", weight_basis: "population",
      from_code_system: "da_2021", to_code_system: "csd_2021"
    )
    too_big = set.entries.build(from_geo: @geo_a, to_geo: @geo_b, weight: 1.5,
      relationship_type: "allocated")
    refute too_big.valid?
  end

  test "weight_checks view sums weights per from_geo" do
    set = Warehouse::GeographyCrosswalkSet.create!(
      name: "DA→CSD", method: "tabular", weight_basis: "population",
      from_code_system: "da_2021", to_code_system: "csd_2021"
    )
    set.entries.create!(from_geo: @geo_a, to_geo: @geo_b, weight: 0.7, relationship_type: "allocated")
    set.entries.create!(from_geo: @geo_a, to_geo: @geo_c, weight: 0.3, relationship_type: "allocated")

    row = Warehouse::Record.connection.execute(
      "SELECT total_weight FROM warehouse.crosswalk_weight_checks WHERE crosswalk_set_id = #{set.id} AND from_geo_id = #{@geo_a.id}"
    ).first
    assert_in_delta 1.0, row["total_weight"].to_f, 1e-9
  end

  test "Allocator creates a derived observation for additive measures" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 100,
      geo_boundary: @geo_a)
    obs.approve!(reviewer: "x")
    canonical = obs.canonical_observation

    set = Warehouse::GeographyCrosswalkSet.create!(
      name: "DA→CSD", method: "tabular", weight_basis: "population",
      from_code_system: "da_2021", to_code_system: "csd_2021"
    )
    set.entries.create!(from_geo: @geo_a, to_geo: @geo_b, weight: 0.7, relationship_type: "allocated")

    result = Warehouse::GeographyCrosswalkSet::Allocator.allocate!(
      crosswalk_set: set, canonical_observation: canonical, target_geo: @geo_b
    )
    derived = result.derived
    assert_equal 70.0, derived.value_numeric
    assert_equal @geo_a.id, derived.original_geo_id
    assert_equal @geo_b.id, derived.derived_geo_id
    assert_equal "crosswalk_allocation", derived.derivation_method
    assert_equal canonical.id, derived.from_canonical_observation_id
  end

  test "Allocator refuses to crosswalk non-aggregable measures" do
    obs = Warehouse::ExtractedObservation.create!(measure: @ratio_measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 7.5, geo_boundary: @geo_a)
    obs.approve!(reviewer: "x")

    set = Warehouse::GeographyCrosswalkSet.create!(
      name: "DA→CSD", method: "tabular", weight_basis: "population",
      from_code_system: "da_2021", to_code_system: "csd_2021"
    )
    set.entries.create!(from_geo: @geo_a, to_geo: @geo_b, weight: 0.5, relationship_type: "allocated")

    assert_raises(Warehouse::GeographyCrosswalkSet::Allocator::IncompatibleMetric) do
      Warehouse::GeographyCrosswalkSet::Allocator.allocate!(
        crosswalk_set: set, canonical_observation: obs.canonical_observation, target_geo: @geo_b
      )
    end
  end

  test "Allocator allows risky-compat metrics with explicit compatibility row" do
    obs = Warehouse::ExtractedObservation.create!(measure: @ratio_measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 7.5, geo_boundary: @geo_a)
    obs.approve!(reviewer: "x")

    set = Warehouse::GeographyCrosswalkSet.create!(
      name: "DA→CSD", method: "tabular", weight_basis: "population",
      from_code_system: "da_2021", to_code_system: "csd_2021"
    )
    set.entries.create!(from_geo: @geo_a, to_geo: @geo_b, weight: 0.5, relationship_type: "allocated")
    Warehouse::CrosswalkMetricCompatibility.create!(crosswalk_set: set, measure: @ratio_measure,
      compatibility: "risky", reason: "test override")

    result = Warehouse::GeographyCrosswalkSet::Allocator.allocate!(
      crosswalk_set: set, canonical_observation: obs.canonical_observation, target_geo: @geo_b
    )
    assert_equal 3.75, result.derived.value_numeric
  end

  test "Allocator refuses when explicit compatibility is not_allowed" do
    obs = Warehouse::ExtractedObservation.create!(measure: @measure, document: @doc,
      measurement_year: 2024, value_type: "actual", value_numeric: 100, geo_boundary: @geo_a)
    obs.approve!(reviewer: "x")

    set = Warehouse::GeographyCrosswalkSet.create!(
      name: "DA→CSD", method: "tabular", weight_basis: "population",
      from_code_system: "da_2021", to_code_system: "csd_2021"
    )
    set.entries.create!(from_geo: @geo_a, to_geo: @geo_b, weight: 0.5, relationship_type: "allocated")
    Warehouse::CrosswalkMetricCompatibility.create!(crosswalk_set: set, measure: @measure,
      compatibility: "not_allowed", reason: "incident review")

    assert_raises(Warehouse::GeographyCrosswalkSet::Allocator::IncompatibleMetric) do
      Warehouse::GeographyCrosswalkSet::Allocator.allocate!(
        crosswalk_set: set, canonical_observation: obs.canonical_observation, target_geo: @geo_b
      )
    end
  end
end
