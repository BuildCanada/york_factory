require "test_helper"

class RawIngestion::OdaNormalizerTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(name: "statcan_oda_ab_test", url: "https://example.com/oda.csv", format: "csv")
    @ingestion = RawIngestion.create!(
      source: @source,
      fetched_at: Time.current,
      raw_file_path: "raw/test/oda.csv",
      checksum: "oda_123",
      status: :pending
    )
  end

  # Real ODA CSV columns from Statistics Canada
  test "parses real ODA CSV format with pruid" do
    csv = <<~CSV
      latitude,longitude,source_id,id,group_id,street_no,street,str_name,str_type,str_dir,unit,city,postal_code,full_addr,city_pcs,str_name_pcs,str_type_pcs,str_dir_pcs,csduid,csdname,pruid,provider
      51.27301,-113.99282,1,abc123,6306961,448,BIG SPRINGS DR SE,BIG SPRINGS,DR,SE,,AIRDRIE,,448 BIG SPRINGS DR SE,AIRDRIE,BIG SPRINGS,DR,SE,4806021,Airdrie,48,City of Airdrie
    CSV

    @ingestion.oda_normalizer.normalize(file_content: csv)

    assert_equal "complete", @ingestion.reload.status
    assert_equal 1, StandardizedAddress.count

    addr = StandardizedAddress.first
    assert_equal "AIRDRIE", addr.city
    assert_equal "AB", addr.province
    assert_equal "448 BIG SPRINGS DR SE", addr.full_address
    assert_equal "BIG SPRINGS", addr.street_name
    assert_equal "448", addr.street_number
    assert_equal "1", addr.source_id
    assert_equal "Airdrie", addr.census_subdivision_name
    assert_in_delta 51.27301, addr.latitude.to_f, 0.001
    assert_in_delta(-113.99282, addr.longitude.to_f, 0.001)
  end

  test "upserts by source_id" do
    csv1 = <<~CSV
      latitude,longitude,source_id,id,group_id,street_no,street,str_name,str_type,str_dir,unit,city,postal_code,full_addr,city_pcs,str_name_pcs,str_type_pcs,str_dir_pcs,csduid,csdname,pruid,provider
      43.0,-79.0,ODA-002,def456,,123,MAIN ST,MAIN,ST,,,Toronto,M5V 1A1,Old Address,,,,,3520005,Toronto,35,City of Toronto
    CSV

    @ingestion.oda_normalizer.normalize(file_content: csv1)
    assert_equal 1, StandardizedAddress.count

    csv2 = <<~CSV
      latitude,longitude,source_id,id,group_id,street_no,street,str_name,str_type,str_dir,unit,city,postal_code,full_addr,city_pcs,str_name_pcs,str_type_pcs,str_dir_pcs,csduid,csdname,pruid,provider
      43.1,-79.1,ODA-002,def456,,123,MAIN ST,MAIN,ST,,,Toronto,M5V 1A1,New Address,,,,,3520005,Toronto,35,City of Toronto
    CSV

    ingestion2 = RawIngestion.create!(
      source: @source, fetched_at: Time.current,
      raw_file_path: "raw/test/oda2.csv", checksum: "oda_456", status: :pending
    )
    ingestion2.oda_normalizer.normalize(file_content: csv2)

    assert_equal 1, StandardizedAddress.count
    assert_equal "New Address", StandardizedAddress.first.full_address
  end

  test "skips rows missing required fields" do
    csv = <<~CSV
      latitude,longitude,source_id,id,group_id,street_no,street,str_name,str_type,str_dir,unit,city,postal_code,full_addr,city_pcs,str_name_pcs,str_type_pcs,str_dir_pcs,csduid,csdname,pruid,provider
      ,,,,,,,,,,,,,,,,,,,,,,
    CSV

    @ingestion.oda_normalizer.normalize(file_content: csv)
    assert_equal 0, StandardizedAddress.count
  end

  test "maps all PRUID codes to provinces" do
    expected = { "10" => "NL", "11" => "PE", "12" => "NS", "13" => "NB",
                 "24" => "QC", "35" => "ON", "46" => "MB", "47" => "SK",
                 "48" => "AB", "59" => "BC", "60" => "YT", "61" => "NT", "62" => "NU" }

    expected.each do |pruid, province|
      assert_equal province, RawIngestion::OdaNormalizer::PRUID_MAP[pruid],
        "PRUID #{pruid} should map to #{province}"
    end
  end
end
