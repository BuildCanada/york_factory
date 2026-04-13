require "test_helper"
require "zip"

class Warehouse::RawIngestion::AddressLoaderTest < ActiveSupport::TestCase
  setup do
    @source = Warehouse::Source.find_or_create_by!(name: "oda_on") do |s|
      s.url = "https://example.com/oda_on.zip"
      s.format = "csv"
      s.fetch_frequency = "manual"
    end
    @ingestion = Warehouse::RawIngestion.create!(source: @source, fetched_at: Time.current, raw_file_path: "test/oda_on", checksum: "oda123", status: :pending)
  end

  test "loads addresses from CSV inside ZIP" do
    zip_content = create_address_zip(<<~CSV)
      id,street_no,str_name,str_type,str_dir,unit,city,pruid,postal_code,full_addr,csduid,csdname,latitude,longitude,provider
      ON-001,123,Main,St,N,,Toronto,35,M5V 1A1,123 Main St N,3520005,Toronto,43.6532,-79.3832,Municipal
    CSV

    @ingestion.address_loader.load(file_content: zip_content)

    assert_equal 1, Warehouse::Address.count
    addr = Warehouse::Address.first
    assert_equal "ON-001", addr.oda_uid
    assert_equal "123", addr.street_number
    assert_equal "Main", addr.street_name
    assert_equal "St", addr.street_type
    assert_equal "N", addr.street_direction
    assert_equal "Toronto", addr.city
    assert_equal "35", addr.province_code
    assert_equal "M5V 1A1", addr.postal_code
    assert_equal "3520005", addr.csd_uid
    assert_in_delta 43.6532, addr.latitude.to_f, 0.001
    assert_in_delta(-79.3832, addr.longitude.to_f, 0.001)
    assert_equal "complete", @ingestion.reload.status
  end

  test "skips rows with missing oda_uid" do
    zip_content = create_address_zip(<<~CSV)
      id,street_no,str_name,str_type,str_dir,unit,city,pruid,postal_code,full_addr,csduid,csdname,latitude,longitude,provider
      ,123,Main,St,,,Toronto,35,M5V 1A1,123 Main St,3520005,Toronto,43.65,-79.38,Municipal
      ON-002,456,King,St,,,Toronto,35,M5V 2B2,456 King St,3520005,Toronto,43.64,-79.39,Municipal
    CSV

    @ingestion.address_loader.load(file_content: zip_content)
    assert_equal 1, Warehouse::Address.count
    assert_equal "ON-002", Warehouse::Address.first.oda_uid
  end

  test "handles upsert on duplicate oda_uid" do
    zip_content1 = create_address_zip(<<~CSV)
      id,street_no,str_name,str_type,str_dir,unit,city,pruid,postal_code,full_addr,csduid,csdname,latitude,longitude,provider
      ON-001,123,Main,St,,,Toronto,35,M5V 1A1,123 Main St,3520005,Toronto,43.65,-79.38,Municipal
    CSV

    @ingestion.address_loader.load(file_content: zip_content1)

    ingestion2 = Warehouse::RawIngestion.create!(source: @source, fetched_at: Time.current, raw_file_path: "test/oda2", checksum: "oda456", status: :pending)
    zip_content2 = create_address_zip(<<~CSV)
      id,street_no,str_name,str_type,str_dir,unit,city,pruid,postal_code,full_addr,csduid,csdname,latitude,longitude,provider
      ON-001,123,Main Updated,Ave,,,Toronto,35,M5V 1A1,123 Main Updated Ave,3520005,Toronto,43.65,-79.38,Municipal
    CSV

    ingestion2.address_loader.load(file_content: zip_content2)

    assert_equal 1, Warehouse::Address.count
    assert_equal "Main Updated", Warehouse::Address.first.street_name
  end

  test "maps PRUID to province_code" do
    zip_content = create_address_zip(<<~CSV)
      id,street_no,str_name,str_type,str_dir,unit,city,pruid,postal_code,full_addr,csduid,csdname,latitude,longitude,provider
      NL-001,1,Water,St,,,St. Johns,10,A1C 1A1,1 Water St,1001519,St. Johns,47.56,-52.71,Municipal
    CSV

    @ingestion.address_loader.load(file_content: zip_content)
    assert_equal "10", Warehouse::Address.first.province_code
  end

  test "fails ingestion on error" do
    assert_raises do
      @ingestion.address_loader.load(file_content: "not a valid zip")
    end

    assert_equal "failed", @ingestion.reload.status
    assert @ingestion.error_message.present?
  end

  private

  def create_address_zip(csv_content)
    buffer = StringIO.new
    Zip::OutputStream.write_buffer(buffer) do |zio|
      zio.put_next_entry("ODA_ON_v1.csv")
      zio.write(csv_content)
    end
    buffer.string
  end
end
