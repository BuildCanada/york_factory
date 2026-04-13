require "test_helper"

class Warehouse::GeoBoundaryTest < ActiveSupport::TestCase
  setup do
    @fsa = Warehouse::GeoBoundary.create!(
      boundary_type: "fsa", geo_uid: "M5V", name_en: "M5V",
      province_code: "35", census_year: 2021, population: 28456
    )
  end

  test "validates presence of boundary_type" do
    boundary = Warehouse::GeoBoundary.new(geo_uid: "X1X", census_year: 2021)
    assert_not boundary.valid?
    assert boundary.errors[:boundary_type].any?
  end

  test "validates presence of geo_uid" do
    boundary = Warehouse::GeoBoundary.new(boundary_type: "fsa", census_year: 2021)
    assert_not boundary.valid?
    assert boundary.errors[:geo_uid].any?
  end

  test "validates uniqueness of geo_uid scoped to boundary_type and census_year" do
    duplicate = Warehouse::GeoBoundary.new(
      boundary_type: "fsa", geo_uid: "M5V", census_year: 2021, name_en: "Duplicate"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:geo_uid].any?
  end

  test "allows same geo_uid for different boundary_types" do
    other = Warehouse::GeoBoundary.new(
      boundary_type: "ct", geo_uid: "M5V", census_year: 2021
    )
    assert other.valid?
  end

  test "by_type scope filters correctly" do
    Warehouse::GeoBoundary.create!(boundary_type: "fed", geo_uid: "35024", census_year: 2021)
    assert_equal 1, Warehouse::GeoBoundary.by_type(:fsa).count
    assert_equal 1, Warehouse::GeoBoundary.by_type(:fed).count
  end

  test "in_province scope filters correctly" do
    Warehouse::GeoBoundary.create!(boundary_type: "fed", geo_uid: "35024", province_code: "35", census_year: 2021)
    Warehouse::GeoBoundary.create!(boundary_type: "fed", geo_uid: "24001", province_code: "24", census_year: 2021)
    assert_equal 2, Warehouse::GeoBoundary.in_province("35").count
  end

  test "search_name scope finds by partial name" do
    Warehouse::GeoBoundary.create!(boundary_type: "fed", geo_uid: "35024", name_en: "Toronto Centre", census_year: 2021)
    assert_equal 1, Warehouse::GeoBoundary.search_name("Toronto").count
    assert_equal 0, Warehouse::GeoBoundary.search_name("Vancouver").count
  end

  test "boundary_type enum includes all expected types" do
    %w[da ct csd fsa fed ped ward pr cd er cma popctr school_board_ward].each do |type|
      assert_includes Warehouse::GeoBoundary.boundary_types.keys, type
    end
  end
end
