require "test_helper"

class Warehouse::Spending::Scrapers::CihrAwardsTest < ActiveSupport::TestCase
  test "normalizes Solr award documents" do
    payload = {
      "response" => {
        "docs" => [
          {
            "id" => "163301",
            "projecttitle" => [ "Granzyme B in Hair Follicle Growth" ],
            "abstract" => [ "Research into hair loss." ],
            "name" => [ "Granville, David J" ],
            "pinamesdelim" => [ "Granville, David J; McElwee, Kevin J" ],
            "orgname" => [ "University of British Columbia" ],
            "region" => [ "British Columbia" ],
            "country" => [ "Canada" ],
            "competitiondate" => [ "201909" ],
            "cihramount2" => [ "$99,927" ],
            "programname2" => [ "Catalyst Grant" ],
            "programtype2" => [ "Operating Grants" ],
            "theme2" => [ "Biomedical" ],
            "instname2" => [ "Musculoskeletal Health and Arthritis" ],
            "keyworddelim" => [ "Alopecia; Granzyme B" ],
            "approvedterm2" => [ "1 year" ]
          }
        ]
      }
    }.to_json

    attributes = parsed_attributes(Warehouse::Spending::Scrapers::CihrAwards, payload).sole

    assert_equal "163301", attributes[:external_key]
    assert_equal "Granzyme B in Hair Follicle Growth", attributes[:title]
    assert_equal "University of British Columbia", attributes[:recipient_name]
    assert_equal "Catalyst Grant", attributes[:program_name]
    assert_equal 2019, attributes[:fiscal_year]
    assert_equal Time.zone.local(2019, 9, 1), attributes[:occurred_at]
    assert_equal BigDecimal("99927"), attributes[:amount]
    assert_equal "BC", attributes[:province_code]
    assert_equal "CA", attributes[:country_code]
    assert_equal "Operating Grants", attributes.dig(:metadata, "program_type")
    assert_includes attributes[:source_url], "applId=163301"
  end

  test "streams canonical NDJSON one award at a time" do
    records = 2.times.map do |index|
      {
        "id" => (index + 1).to_s,
        "projecttitle" => [ "Project #{index + 1}" ],
        "competitiondate" => [ "202401" ],
        "cihramount2" => [ "$1,000" ]
      }
    end
    payload = StringIO.new(records.map { |record| JSON.generate(record) }.join("\n") << "\n")

    attributes = parsed_attributes(Warehouse::Spending::Scrapers::CihrAwards, payload)

    assert_equal %w[1 2], attributes.pluck(:external_key)
    assert_equal [ "Project 1", "Project 2" ], attributes.pluck(:title)
  end

  private

  def parsed_attributes(scraper_class, payload)
    source = Struct.new(:url).new("https://example.test/awards")
    ingestion = Struct.new(:source).new(source)
    [].tap do |attributes|
      scraper_class.new(ingestion).send(:each_attributes, payload) { |value| attributes << value }
    end
  end
end
