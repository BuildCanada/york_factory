require "test_helper"

class RawIngestion::OdbizNormalizerTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(name: "statcan_odbiz_test", url: "https://example.com/odbiz.csv", format: "csv_zip")
    @ingestion = RawIngestion.create!(
      source: @source,
      fetched_at: Time.current,
      raw_file_path: "raw/test/odbiz.csv",
      checksum: "odbiz_123",
      status: :pending
    )
  end

  # Real ODBiz CSV columns from Statistics Canada
  test "parses real ODBiz CSV format" do
    csv = <<~CSV
      idx,business_name,alt_business_name,business_sector,business_subsector,business_description,business_id_no,licence_number,licence_type,derived_NAICS,source_NAICS_primary,source_NAICS_secondary,NAICS_descr,NAICS_descr2,latitude,longitude,full_address,postal_code,unit,street_no,street_name,street_direction,street_type,city,prov_terr,total_no_employees,status,provider,geo_source,CSDUID,CSDNAME,PRUID
      abc123,Acme Corp,Acme Trading,..,..,..,BN12345,..,..,44,..,..,Computer Systems Design,..,43.6532,-79.3832,"123 Main St, Toronto ON",M5V 1A1,,123,Main,,St,Toronto,ON,10-19,..,City of Toronto,Source,3520005,Toronto,35
    CSV

    @ingestion.odbiz_normalizer.normalize(file_content: csv)

    assert_equal "complete", @ingestion.reload.status
    assert_equal 1, BusinessEstablishment.count

    be = BusinessEstablishment.first
    assert_equal "Acme Corp", be.business_name
    assert_equal "Acme Trading", be.trade_name
    assert_equal "BN12345", be.business_number
    assert_equal "44", be.naics_code
    assert_equal "Computer Systems Design", be.naics_description
    assert_equal "10-19", be.employee_size_range
    assert_equal "ON", be.province
    assert_equal "Toronto", be.city
    assert_equal "odbiz", be.source_system
    assert_in_delta 43.6532, be.latitude.to_f, 0.001
  end

  test "skips rows without business_name" do
    csv = <<~CSV
      idx,business_name,alt_business_name,business_sector,business_subsector,business_description,business_id_no,licence_number,licence_type,derived_NAICS,source_NAICS_primary,source_NAICS_secondary,NAICS_descr,NAICS_descr2,latitude,longitude,full_address,postal_code,unit,street_no,street_name,street_direction,street_type,city,prov_terr,total_no_employees,status,provider,geo_source,CSDUID,CSDNAME,PRUID
      abc,,..,..,..,..,..,..,..,..,..,..,..,..,,,,,,,,,,,ON,,,,,,,
    CSV

    @ingestion.odbiz_normalizer.normalize(file_content: csv)
    assert_equal 0, BusinessEstablishment.count
  end

  test "skips rows without province" do
    csv = <<~CSV
      idx,business_name,alt_business_name,business_sector,business_subsector,business_description,business_id_no,licence_number,licence_type,derived_NAICS,source_NAICS_primary,source_NAICS_secondary,NAICS_descr,NAICS_descr2,latitude,longitude,full_address,postal_code,unit,street_no,street_name,street_direction,street_type,city,prov_terr,total_no_employees,status,provider,geo_source,CSDUID,CSDNAME,PRUID
      abc,Test Corp,..,..,..,..,..,..,..,..,..,..,..,..,,,,,,,,,,,,,,,,,,,
    CSV

    @ingestion.odbiz_normalizer.normalize(file_content: csv)
    assert_equal 0, BusinessEstablishment.count
  end
end
