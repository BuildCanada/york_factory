require "test_helper"

class RawIngestion::CorporateNormalizerTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(name: "corporate_federal_ised_test", url: "https://example.com/corps.xml", format: "xml_zip")
    @ingestion = RawIngestion.create!(
      source: @source,
      fetched_at: Time.current,
      raw_file_path: "raw/test/corps.xml",
      checksum: "corp_xml_123",
      status: :pending
    )
  end

  # Matches the real ISED OPEN_DATA XML structure:
  # <corporation corporationId="...">
  #   <names><name code="1" current="true">...</name></names>
  #   <statuses><status code="1" current="true"/></statuses>
  #   <acts><act code="6" current="true"/></acts>
  #   <activities><activity code="1" date="2020-01-15T00:00:00"/></activities>
  #   <addresses><address code="2" current="true">...</address></addresses>
  #   <businessNumbers><businessNumber>123456789</businessNumber></businessNumbers>
  # </corporation>

  test "parses real ISED XML structure" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <cc:corpcan xmlns:cc="http://www.ic.gc.ca/corpcan" reportId="OPEN_DATA" date="2026-01-01T00:00:00">
      <corporations>
        <corporation corporationId="12345">
          <names>
            <name code="1" current="true" effectiveDate="2020-01-15T00:00:00">Test Federal Corp</name>
          </names>
          <statuses>
            <status code="1" current="true" effectiveDate="2020-01-15T00:00:00"/>
          </statuses>
          <acts>
            <act code="6" current="true" effectiveDate="2020-01-15T00:00:00"/>
          </acts>
          <activities>
            <activity code="1" date="2020-01-15T00:00:00"/>
          </activities>
          <addresses>
            <address code="2" current="true" effectiveDate="2020-01-15T00:00:00">
              <addressLine>123 MAIN ST</addressLine>
              <city>OTTAWA</city>
              <province code="ON"/>
              <country code="CA"/>
              <postalCode>K1A 0A1</postalCode>
            </address>
          </addresses>
          <businessNumbers>
            <businessNumber>123456789RC0001</businessNumber>
          </businessNumbers>
        </corporation>
      </corporations>
      </cc:corpcan>
    XML

    @ingestion.corporate_normalizer.normalize(file_content: xml)

    assert_equal "complete", @ingestion.reload.status
    assert_equal 1, CorporateEntity.count

    corp = CorporateEntity.first
    assert_equal "federal", corp.jurisdiction
    assert_equal "12345", corp.registry_id
    assert_equal "Test Federal Corp", corp.legal_name
    assert_equal "Active", corp.status
    assert_equal "CBCA", corp.governing_act
    assert_equal "123456789RC0001", corp.business_number
    assert_equal "ON", corp.registered_office_province
    assert_equal "K1A 0A1", corp.registered_office_postal_code
    assert_equal "123 MAIN ST", corp.registered_office_address
    assert_equal Date.new(2020, 1, 15), corp.incorporation_date
    assert_equal "ised_xml", corp.source_system
  end

  test "handles empty XML gracefully" do
    xml = <<~XML
      <?xml version="1.0"?>
      <cc:corpcan xmlns:cc="http://www.ic.gc.ca/corpcan">
      <corporations></corporations>
      </cc:corpcan>
    XML

    @ingestion.corporate_normalizer.normalize(file_content: xml)
    assert_equal "complete", @ingestion.reload.status
    assert_equal 0, CorporateEntity.count
  end

  test "skips corporations without registry_id or name" do
    xml = <<~XML
      <?xml version="1.0"?>
      <cc:corpcan xmlns:cc="http://www.ic.gc.ca/corpcan">
      <corporations>
        <corporation corporationId="">
          <names><name code="1" current="true">No Number Corp</name></names>
        </corporation>
        <corporation corporationId="99999">
          <names></names>
        </corporation>
      </corporations>
      </cc:corpcan>
    XML

    @ingestion.corporate_normalizer.normalize(file_content: xml)
    assert_equal 0, CorporateEntity.count
  end

  test "upserts on re-ingestion" do
    xml = <<~XML
      <?xml version="1.0"?>
      <cc:corpcan xmlns:cc="http://www.ic.gc.ca/corpcan">
      <corporations>
        <corporation corporationId="11111">
          <names><name code="1" current="true">Original Name</name></names>
          <statuses><status code="1" current="true"/></statuses>
          <activities><activity code="1" date="2020-01-01T00:00:00"/></activities>
        </corporation>
      </corporations>
      </cc:corpcan>
    XML

    @ingestion.corporate_normalizer.normalize(file_content: xml)
    assert_equal 1, CorporateEntity.count

    # Re-ingest with updated name
    xml2 = xml.gsub("Original Name", "Updated Name")
    ingestion2 = RawIngestion.create!(
      source: @source, fetched_at: Time.current,
      raw_file_path: "raw/test/corps2.xml", checksum: "corp_xml_456", status: :pending
    )
    ingestion2.corporate_normalizer.normalize(file_content: xml2)

    assert_equal 1, CorporateEntity.count
    assert_equal "Updated Name", CorporateEntity.first.legal_name
  end

  test "extracts dissolution date from activities" do
    xml = <<~XML
      <?xml version="1.0"?>
      <cc:corpcan xmlns:cc="http://www.ic.gc.ca/corpcan">
      <corporations>
        <corporation corporationId="22222">
          <names><name code="1" current="true">Dissolved Corp</name></names>
          <statuses><status code="11" current="true"/></statuses>
          <activities>
            <activity code="1" date="2015-06-01T00:00:00"/>
            <activity code="101" date="2023-12-31T00:00:00"/>
          </activities>
        </corporation>
      </corporations>
      </cc:corpcan>
    XML

    @ingestion.corporate_normalizer.normalize(file_content: xml)

    corp = CorporateEntity.first
    assert_equal "Dissolved", corp.status
    assert_equal Date.new(2015, 6, 1), corp.incorporation_date
    assert_equal Date.new(2023, 12, 31), corp.dissolution_date
  end

  test "picks current name from multiple names" do
    xml = <<~XML
      <?xml version="1.0"?>
      <cc:corpcan xmlns:cc="http://www.ic.gc.ca/corpcan">
      <corporations>
        <corporation corporationId="33333">
          <names>
            <name code="1" effectiveDate="2010-01-01T00:00:00" expiryDate="2020-01-01T00:00:00">Old Name</name>
            <name code="1" current="true" effectiveDate="2020-01-01T00:00:00">Current Name</name>
          </names>
          <statuses><status code="1" current="true"/></statuses>
          <activities><activity code="1" date="2010-01-01T00:00:00"/></activities>
        </corporation>
      </corporations>
      </cc:corpcan>
    XML

    @ingestion.corporate_normalizer.normalize(file_content: xml)

    corp = CorporateEntity.first
    assert_equal "Current Name", corp.legal_name
  end
end
