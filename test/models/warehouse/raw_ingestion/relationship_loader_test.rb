require "test_helper"

class RawIngestion::RelationshipLoaderTest < ActiveSupport::TestCase
  setup do
    @source = Source.find_or_create_by!(name: "statcan_geo_relationship") do |s|
      s.url = "https://example.com/rel.csv"
      s.format = "csv"
      s.fetch_frequency = "manual"
    end
    @ingestion = RawIngestion.create!(source: @source, fetched_at: Time.current, raw_file_path: "test/rel", checksum: "rel123", status: :pending)

    @da = GeoBoundary.create!(boundary_type: "da", geo_uid: "35010001", census_year: 2021)
    @fsa = GeoBoundary.create!(boundary_type: "fsa", geo_uid: "M5V", census_year: 2021)
    @ct = GeoBoundary.create!(boundary_type: "ct", geo_uid: "5350001.00", census_year: 2021)
    @csd = GeoBoundary.create!(boundary_type: "csd", geo_uid: "3520005", census_year: 2021)
  end

  test "creates relationships from CSV" do
    csv = <<~CSV
      DAUID,CFSAUID,CTUID,CSDUID
      35010001,M5V,5350001.00,3520005
    CSV

    @ingestion.relationship_loader.load(csv_content: csv)

    assert_equal 3, GeoRelationship.count
    assert GeoRelationship.exists?(da: @da, parent: @fsa, relationship_type: "da_fsa")
    assert GeoRelationship.exists?(da: @da, parent: @ct, relationship_type: "da_ct")
    assert GeoRelationship.exists?(da: @da, parent: @csd, relationship_type: "da_csd")
    assert_equal "complete", @ingestion.reload.status
  end

  test "skips relationships where parent boundary not found" do
    csv = <<~CSV
      DAUID,CFSAUID,CTUID,CSDUID
      35010001,UNKNOWN,5350001.00,3520005
    CSV

    @ingestion.relationship_loader.load(csv_content: csv)

    # FSA "UNKNOWN" not in DB, so only CT and CSD relationships created
    assert_equal 2, GeoRelationship.count
    assert_not GeoRelationship.exists?(relationship_type: "da_fsa")
  end

  test "skips rows where DA not found" do
    csv = <<~CSV
      DAUID,CFSAUID,CTUID,CSDUID
      99999999,M5V,5350001.00,3520005
    CSV

    @ingestion.relationship_loader.load(csv_content: csv)
    assert_equal 0, GeoRelationship.count
  end

  test "handles duplicate CSV rows via upsert" do
    # First load creates the relationships
    csv1 = <<~CSV
      DAUID,CFSAUID,CTUID,CSDUID
      35010001,M5V,5350001.00,3520005
    CSV

    @ingestion.relationship_loader.load(csv_content: csv1)
    assert_equal 3, GeoRelationship.count

    # Second load with same data upserts without error
    ingestion2 = RawIngestion.create!(source: @source, fetched_at: Time.current, raw_file_path: "test/rel2", checksum: "rel789", status: :pending)
    csv2 = <<~CSV
      DAUID,CFSAUID,CTUID,CSDUID
      35010001,M5V,5350001.00,3520005
    CSV

    ingestion2.relationship_loader.load(csv_content: csv2)
    assert_equal 3, GeoRelationship.count
  end

  test "fails ingestion on error" do
    ingestion = RawIngestion.create!(source: @source, fetched_at: Time.current, raw_file_path: "test/rel_err", checksum: "rel456", status: :pending)

    assert_raises do
      ingestion.relationship_loader.load(csv_content: nil)
    end

    assert_equal "failed", ingestion.reload.status
  end
end
