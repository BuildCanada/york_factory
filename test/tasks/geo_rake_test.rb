require "test_helper"
require "rake"

class GeoRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("geo:build_crosswalk")

    # Create boundary hierarchy:
    #   DA1 (pop 600) → FSA "M5V", CT "001", CSD "3520005"
    #   DA2 (pop 400) → FSA "M5V", CT "002", CSD "3520005"
    #   DA3 (pop 500) → FSA "M5H", CT "002", CSD "3520006"
    @fsa_m5v = Warehouse::GeoBoundary.create!(boundary_type: "fsa", geo_uid: "M5V", census_year: 2021)
    @fsa_m5h = Warehouse::GeoBoundary.create!(boundary_type: "fsa", geo_uid: "M5H", census_year: 2021)
    @ct_001 = Warehouse::GeoBoundary.create!(boundary_type: "ct", geo_uid: "001", census_year: 2021)
    @ct_002 = Warehouse::GeoBoundary.create!(boundary_type: "ct", geo_uid: "002", census_year: 2021)
    @csd_005 = Warehouse::GeoBoundary.create!(boundary_type: "csd", geo_uid: "3520005", census_year: 2021)
    @csd_006 = Warehouse::GeoBoundary.create!(boundary_type: "csd", geo_uid: "3520006", census_year: 2021)

    @da1 = Warehouse::GeoBoundary.create!(boundary_type: "da", geo_uid: "DA1", census_year: 2021, population: 600)
    @da2 = Warehouse::GeoBoundary.create!(boundary_type: "da", geo_uid: "DA2", census_year: 2021, population: 400)
    @da3 = Warehouse::GeoBoundary.create!(boundary_type: "da", geo_uid: "DA3", census_year: 2021, population: 500)

    # DA→FSA relationships
    Warehouse::GeoRelationship.create!(da: @da1, parent: @fsa_m5v, relationship_type: "da_fsa")
    Warehouse::GeoRelationship.create!(da: @da2, parent: @fsa_m5v, relationship_type: "da_fsa")
    Warehouse::GeoRelationship.create!(da: @da3, parent: @fsa_m5h, relationship_type: "da_fsa")

    # DA→CT relationships
    Warehouse::GeoRelationship.create!(da: @da1, parent: @ct_001, relationship_type: "da_ct")
    Warehouse::GeoRelationship.create!(da: @da2, parent: @ct_002, relationship_type: "da_ct")
    Warehouse::GeoRelationship.create!(da: @da3, parent: @ct_002, relationship_type: "da_ct")

    # DA→CSD relationships
    Warehouse::GeoRelationship.create!(da: @da1, parent: @csd_005, relationship_type: "da_csd")
    Warehouse::GeoRelationship.create!(da: @da2, parent: @csd_005, relationship_type: "da_csd")
    Warehouse::GeoRelationship.create!(da: @da3, parent: @csd_006, relationship_type: "da_csd")
  end

  test "build_tabular_crosswalks creates FSA↔CT crosswalks with correct weights" do
    build_tabular_crosswalks

    # M5V contains DA1(600)→CT001 and DA2(400)→CT002
    xwalk = Warehouse::GeoCrosswalk.find_by(source: @fsa_m5v, target: @ct_001)
    assert_not_nil xwalk, "Expected crosswalk from M5V → CT 001"
    assert_equal 600, xwalk.overlap_population
    assert_equal 1, xwalk.da_count
    # Weight: 600 / (600+400) = 0.6
    assert_in_delta 0.6, xwalk.weight_source_to_target.to_f, 0.001

    xwalk2 = Warehouse::GeoCrosswalk.find_by(source: @fsa_m5v, target: @ct_002)
    assert_not_nil xwalk2, "Expected crosswalk from M5V → CT 002"
    assert_equal 400, xwalk2.overlap_population
    assert_in_delta 0.4, xwalk2.weight_source_to_target.to_f, 0.001
  end

  test "build_tabular_crosswalks creates CT↔CSD crosswalks" do
    build_tabular_crosswalks

    # CT 001 has DA1(600) in CSD 3520005
    xwalk = Warehouse::GeoCrosswalk.find_by(source: @ct_001, target: @csd_005)
    assert_not_nil xwalk, "Expected crosswalk from CT 001 → CSD 3520005"
    assert_equal 600, xwalk.overlap_population
    # CT 001 total = 600, all in CSD 005 → weight = 1.0
    assert_in_delta 1.0, xwalk.weight_source_to_target.to_f, 0.001
  end

  test "build_tabular_crosswalks computes target_to_source weight correctly" do
    build_tabular_crosswalks

    # CT 002 contains DA2(400, in M5V) + DA3(500, in M5H) = 900 total
    # CT 002 → M5V overlap = 400, target_to_source weight = 400/900
    xwalk = Warehouse::GeoCrosswalk.find_by(source: @fsa_m5v, target: @ct_002)
    assert_not_nil xwalk
    assert_in_delta 0.4444, xwalk.weight_target_to_source.to_f, 0.001
  end

  test "crosswalk_query returns parameterized results with correct types" do
    rows = crosswalk_query("da_fsa", "da_ct", "fsa", "ct")
    records = rows.to_a
    assert records.size > 0, "Expected crosswalk query to return results"
    record = records.first
    assert_equal "fsa", record["source_type"]
    assert_equal "ct", record["target_type"]
  end

  test "insert_crosswalks handles empty result set" do
    empty_result = ActiveRecord::Base.connection.execute("SELECT 1 WHERE false")
    insert_crosswalks(empty_result)
    assert_equal 0, Warehouse::GeoCrosswalk.count
  end

  test "zero population DAs are excluded from crosswalks" do
    da_zero = Warehouse::GeoBoundary.create!(boundary_type: "da", geo_uid: "DA_ZERO", census_year: 2021, population: 0)
    fsa_z = Warehouse::GeoBoundary.create!(boundary_type: "fsa", geo_uid: "Z0Z", census_year: 2021)
    ct_z = Warehouse::GeoBoundary.create!(boundary_type: "ct", geo_uid: "Z001", census_year: 2021)

    Warehouse::GeoRelationship.create!(da: da_zero, parent: fsa_z, relationship_type: "da_fsa")
    Warehouse::GeoRelationship.create!(da: da_zero, parent: ct_z, relationship_type: "da_ct")

    build_tabular_crosswalks
    assert_nil Warehouse::GeoCrosswalk.find_by(source: fsa_z, target: ct_z)
  end

  test "crosswalk weights sum to 1.0 for a source" do
    build_tabular_crosswalks

    # M5V → CT: should have weights summing to 1.0
    xwalks = Warehouse::GeoCrosswalk.where(source: @fsa_m5v, source_type: "fsa", target_type: "ct")
    total_weight = xwalks.sum { |x| x.weight_source_to_target.to_f }
    assert_in_delta 1.0, total_weight, 0.001
  end
end
