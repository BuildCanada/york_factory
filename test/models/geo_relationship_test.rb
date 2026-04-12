require "test_helper"

class GeoRelationshipTest < ActiveSupport::TestCase
  setup do
    @da = GeoBoundary.create!(boundary_type: "da", geo_uid: "35200001", census_year: 2021, population: 500)
    @fsa = GeoBoundary.create!(boundary_type: "fsa", geo_uid: "M5V", census_year: 2021)
    @ct = GeoBoundary.create!(boundary_type: "ct", geo_uid: "5350001.00", census_year: 2021)
  end

  test "validates presence of relationship_type" do
    rel = GeoRelationship.new(da: @da, parent: @fsa)
    assert_not rel.valid?
    assert rel.errors[:relationship_type].any?
  end

  test "validates uniqueness of da_id scoped to parent_id and relationship_type" do
    GeoRelationship.create!(da: @da, parent: @fsa, relationship_type: "da_fsa")
    duplicate = GeoRelationship.new(da: @da, parent: @fsa, relationship_type: "da_fsa")
    assert_not duplicate.valid?
  end

  test "same DA can belong to different parent types" do
    rel1 = GeoRelationship.create!(da: @da, parent: @fsa, relationship_type: "da_fsa")
    rel2 = GeoRelationship.create!(da: @da, parent: @ct, relationship_type: "da_ct")
    assert rel1.persisted?
    assert rel2.persisted?
  end
end
