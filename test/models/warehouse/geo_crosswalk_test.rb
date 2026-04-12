require "test_helper"

class Warehouse::GeoCrosswalkTest < ActiveSupport::TestCase
  setup do
    @fsa = Warehouse::GeoBoundary.create!(boundary_type: "fsa", geo_uid: "M5V", census_year: 2021, population: 28000)
    @fed = Warehouse::GeoBoundary.create!(boundary_type: "fed", geo_uid: "35024", name_en: "Toronto Centre", census_year: 2021, population: 100000)
  end

  test "validates uniqueness of source_id scoped to target_id and census_year" do
    Warehouse::GeoCrosswalk.create!(
      source: @fsa, target: @fed,
      source_type: "fsa", target_type: "fed",
      overlap_population: 20000, weight_source_to_target: 0.71,
      weight_target_to_source: 0.20, da_count: 34, census_year: 2021
    )
    duplicate = Warehouse::GeoCrosswalk.new(
      source: @fsa, target: @fed,
      source_type: "fsa", target_type: "fed",
      census_year: 2021
    )
    assert_not duplicate.valid?
  end

  test "from_type scope filters by source_type" do
    Warehouse::GeoCrosswalk.create!(
      source: @fsa, target: @fed,
      source_type: "fsa", target_type: "fed",
      overlap_population: 20000, weight_source_to_target: 0.71,
      da_count: 34, census_year: 2021
    )
    assert_equal 1, Warehouse::GeoCrosswalk.from_type("fsa").count
    assert_equal 0, Warehouse::GeoCrosswalk.from_type("ct").count
  end

  test "to_type scope filters by target_type" do
    Warehouse::GeoCrosswalk.create!(
      source: @fsa, target: @fed,
      source_type: "fsa", target_type: "fed",
      overlap_population: 20000, weight_source_to_target: 0.71,
      da_count: 34, census_year: 2021
    )
    assert_equal 1, Warehouse::GeoCrosswalk.to_type("fed").count
    assert_equal 0, Warehouse::GeoCrosswalk.to_type("ped").count
  end

  test "population weights are computed correctly" do
    # Simulate: FSA M5V has 2 DAs, one in FED 35024 (pop 300) and one in FED 35025 (pop 700)
    fed2 = Warehouse::GeoBoundary.create!(boundary_type: "fed", geo_uid: "35025", census_year: 2021)

    cw1 = Warehouse::GeoCrosswalk.create!(
      source: @fsa, target: @fed,
      source_type: "fsa", target_type: "fed",
      overlap_population: 300, weight_source_to_target: 0.30,
      weight_target_to_source: 0.003, da_count: 1, census_year: 2021
    )
    cw2 = Warehouse::GeoCrosswalk.create!(
      source: @fsa, target: fed2,
      source_type: "fsa", target_type: "fed",
      overlap_population: 700, weight_source_to_target: 0.70,
      weight_target_to_source: 0.007, da_count: 1, census_year: 2021
    )

    # Weights from FSA→FED should sum to ~1.0
    total_weight = cw1.weight_source_to_target + cw2.weight_source_to_target
    assert_in_delta 1.0, total_weight, 0.01
  end
end
