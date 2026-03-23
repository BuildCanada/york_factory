require "test_helper"

class RawIngestion::ProvincialScraperTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(name: "corporate_on_test", url: "https://example.com", format: "html")
    @ingestion = RawIngestion.create!(
      source: @source,
      fetched_at: Time.current,
      raw_file_path: "raw/test/on.html",
      checksum: "on_123",
      status: :pending
    )

    # Seed business establishments for provincial search
    BusinessEstablishment.create!(business_name: "Test Ontario Corp", province: "ON")
    BusinessEstablishment.create!(business_name: "Another ON Biz", province: "ON")
    BusinessEstablishment.create!(business_name: "BC Only Biz", province: "BC")
  end

  test "seed_names_for_province returns correct names" do
    scraper = @ingestion.ontario_obr_scraper
    names = scraper.send(:seed_names_for_province, "ON")

    assert_includes names, "Test Ontario Corp"
    assert_includes names, "Another ON Biz"
    assert_not_includes names, "BC Only Biz"
  end

  test "scraping_progress is saved and retrieved" do
    scraper = @ingestion.ontario_obr_scraper

    scraper.send(:save_scraping_progress, "last_searched_index", 42)

    assert_equal 42, scraper.send(:get_scraping_progress, "last_searched_index")
  end

  test "map_result produces valid corporate entity hash" do
    scraper = @ingestion.ontario_obr_scraper

    result = scraper.send(:map_result, {
      name: "Test Corp Ltd.",
      registry_id: "12345",
      status: "Active"
    })

    assert_equal "on", result[:jurisdiction]
    assert_equal "12345", result[:registry_id]
    assert_equal "Test Corp Ltd.", result[:legal_name]
    assert_equal "Active", result[:status]
    assert_equal "ON", result[:registered_office_province]
    assert_equal "on_obr", result[:source_system]
  end

  test "map_result skips records without registry_id" do
    scraper = @ingestion.ontario_obr_scraper

    result = scraper.send(:map_result, { name: "No Number", registry_id: "", status: "Active" })
    assert_nil result
  end
end
