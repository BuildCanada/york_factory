require "test_helper"
require "zip"

class Warehouse::RawIngestion::BoundaryLoaderTest < ActiveSupport::TestCase
  setup do
    @source = Warehouse::Source.find_or_create_by!(name: "statcan_boundary_fsa") do |s|
      s.url = "https://example.com/fsa.zip"
      s.format = "shapefile"
      s.fetch_frequency = "manual"
    end
    @ingestion = Warehouse::RawIngestion.create!(source: @source, fetched_at: Time.current, raw_file_path: "test/fsa", checksum: "abc123", status: :pending)
  end

  test "detect_boundary_type returns correct type for known source" do
    assert_equal "fsa", @ingestion.boundary_loader.send(:detect_boundary_type)
  end

  test "detect_boundary_type returns nil for unknown source" do
    source = Warehouse::Source.find_or_create_by!(name: "unknown_source_#{SecureRandom.hex(4)}") do |s|
      s.url = "https://example.com"
      s.format = "shapefile"
      s.fetch_frequency = "manual"
    end
    ingestion = Warehouse::RawIngestion.create!(source: source, fetched_at: Time.current, raw_file_path: "test/unknown", checksum: "xyz", status: :pending)
    assert_nil ingestion.boundary_loader.send(:detect_boundary_type)
  end

  test "load fails ingestion for unknown boundary type" do
    source = Warehouse::Source.find_or_create_by!(name: "unknown_source_#{SecureRandom.hex(4)}") do |s|
      s.url = "https://example.com"
      s.format = "shapefile"
      s.fetch_frequency = "manual"
    end
    ingestion = Warehouse::RawIngestion.create!(source: source, fetched_at: Time.current, raw_file_path: "test/unknown", checksum: "xyz2", status: :pending)

    ingestion.boundary_loader.load(file_content: "fake")
    ingestion.reload
    assert_equal "failed", ingestion.status
    assert_match(/Unknown boundary type/, ingestion.error_message)
  end

  test "load fails ingestion when no shp file in archive" do
    zip_content = create_zip_without_shp
    @ingestion.boundary_loader.load(file_content: zip_content)
    @ingestion.reload
    assert_equal "failed", @ingestion.status
    assert_match(/No .shp file/, @ingestion.error_message)
  end

  test "normalize_geometry wraps Polygon in MultiPolygon" do
    factory = RGeo::Cartesian.simple_factory(srid: 4326)
    polygon = factory.polygon(
      factory.linear_ring([
        factory.point(0, 0), factory.point(1, 0), factory.point(1, 1), factory.point(0, 1), factory.point(0, 0)
      ])
    )

    result = @ingestion.boundary_loader.send(:normalize_geometry, polygon)
    assert_kind_of RGeo::Feature::MultiPolygon, result
    assert_equal 1, result.num_geometries
  end

  test "normalize_geometry passes MultiPolygon through" do
    factory = RGeo::Cartesian.simple_factory(srid: 4326)
    polygon = factory.polygon(
      factory.linear_ring([
        factory.point(0, 0), factory.point(1, 0), factory.point(1, 1), factory.point(0, 1), factory.point(0, 0)
      ])
    )
    multi = factory.multi_polygon([ polygon ])

    result = @ingestion.boundary_loader.send(:normalize_geometry, multi)
    assert_equal multi, result
  end

  test "normalize_geometry returns nil for non-polygon geometry" do
    factory = RGeo::Cartesian.simple_factory(srid: 4326)
    point = factory.point(0, 0)

    result = @ingestion.boundary_loader.send(:normalize_geometry, point)
    assert_nil result
  end

  test "BOUNDARY_TYPE_MAP includes all source names" do
    expected_sources = %w[
      statcan_boundary_da statcan_boundary_ct statcan_boundary_csd statcan_boundary_fsa
      elections_canada_fed statcan_boundary_pr statcan_boundary_cd statcan_boundary_er
      statcan_boundary_cma statcan_boundary_popctr
      ped_ontario ped_alberta ped_bc ped_quebec ped_manitoba ped_manitoba_wpg
      ped_saskatchewan ped_new_brunswick ped_yukon ped_nwt
      ward_toronto
      sbw_tdsb sbw_tcdsb sbw_viamonde sbw_monavenir
    ]
    expected_sources.each do |source_name|
      assert_includes Warehouse::RawIngestion::BoundaryLoader::BOUNDARY_TYPE_MAP.keys, source_name,
        "Missing source: #{source_name}"
    end
  end

  test "CUSTOM_FIELD_MAP entries have required keys" do
    Warehouse::RawIngestion::BoundaryLoader::CUSTOM_FIELD_MAP.each do |source, fields|
      assert fields.key?(:uid), "#{source} missing :uid"
      assert fields.key?(:name_en), "#{source} missing :name_en"
    end
  end

  test "elections_canada_fed has province_from_uid and source_srid" do
    custom = Warehouse::RawIngestion::BoundaryLoader::CUSTOM_FIELD_MAP["elections_canada_fed"]
    assert custom[:province_from_uid], "elections_canada_fed should derive province from UID"
    assert_equal 3347, custom[:source_srid], "elections_canada_fed should use EPSG:3347"
  end

  test "projected PED sources have source_srid" do
    {
      "ped_quebec" => 32198,
      "ped_manitoba" => 32614,
      "ped_manitoba_wpg" => 32614,
      "ped_saskatchewan" => 32613,
      "ped_yukon" => 3578,
      "ped_nwt" => 3580
    }.each do |source, expected_srid|
      custom = Warehouse::RawIngestion::BoundaryLoader::CUSTOM_FIELD_MAP[source]
      assert_equal expected_srid, custom[:source_srid], "#{source} should use EPSG:#{expected_srid}"
    end
  end

  test "non-projected PED sources have no source_srid" do
    %w[ped_ontario ped_alberta ped_bc ped_new_brunswick].each do |source|
      custom = Warehouse::RawIngestion::BoundaryLoader::CUSTOM_FIELD_MAP[source]
      assert_nil custom[:source_srid], "#{source} should not have source_srid (WGS84)"
    end
  end

  test "all PED sources have province_code or derive province" do
    ped_sources = Warehouse::RawIngestion::BoundaryLoader::BOUNDARY_TYPE_MAP.select { |_, v| v == "ped" }
    ped_sources.each_key do |source|
      custom = Warehouse::RawIngestion::BoundaryLoader::CUSTOM_FIELD_MAP[source]
      next unless custom
      has_province = custom[:province_code] || custom[:province_from_uid]
      # Ontario, Alberta, BC have PRUID in the shapefile (no custom province needed)
      next if %w[ped_ontario ped_alberta ped_bc].include?(source)
      assert has_province, "#{source} must specify province_code or province_from_uid"
    end
  end

  test "school board ward entries have uid_prefix and name_prefix" do
    %w[sbw_tdsb sbw_tcdsb sbw_viamonde sbw_monavenir].each do |source|
      custom = Warehouse::RawIngestion::BoundaryLoader::CUSTOM_FIELD_MAP[source]
      assert custom[:uid_prefix], "#{source} missing uid_prefix"
      assert custom[:name_prefix], "#{source} missing name_prefix"
      assert_equal "35", custom[:province_code], "#{source} should be in Ontario (35)"
    end
  end

  private

  def create_zip_without_shp
    buffer = StringIO.new
    Zip::OutputStream.write_buffer(buffer) do |zio|
      zio.put_next_entry("readme.txt")
      zio.write("No shapefile here")
    end
    buffer.string
  end
end
