require "test_helper"

class Warehouse::Spending::Scrapers::NsercAwardsTest < ActiveSupport::TestCase
  test "normalizes NSERC DataTables listing rows" do
    payload = {
      "iTotalRecords" => 1,
      "iTotalDisplayRecords" => 1,
      "aaData" => [
        [
          "Bernier, Martin",
          "Math Conference - Aug. 1999 in China",
          "40,373.00",
          "1999-2000",
          "Miscellaneous Grants",
          "156118"
        ]
      ]
    }.to_json

    attributes = parsed_attributes(payload).sole

    assert_equal "156118", attributes[:external_key]
    assert_equal "Math Conference - Aug. 1999 in China", attributes[:title]
    assert_equal "Bernier, Martin", attributes[:recipient_name]
    assert_equal "Miscellaneous Grants", attributes[:program_name]
    assert_equal 1999, attributes[:fiscal_year]
    assert_equal Time.zone.local(1999, 4, 1), attributes[:occurred_at]
    assert_equal BigDecimal("40373"), attributes[:amount]
    assert_equal "CA", attributes[:country_code]
    assert_includes attributes[:source_url], "id=156118"
  end

  test "streams the canonical CSV produced by the current open-data collector" do
    payload = StringIO.new(<<~CSV)
      external_id,application_id,recipient_name,recipient_organization,title,description,award_amount,fiscal_year,program,program_id,province,country,source_url
      305407-2017-2024,305407-2017,"Smol, John",Queen's University,Northern lakes,Project summary,24000,2024,Northern Supplement,RGPNS,Ontario,CANADA,https://example.test/2024.csv
    CSV

    attributes = parsed_attributes(payload).sole

    assert_equal "305407-2017-2024", attributes[:external_key]
    assert_equal "Queen's University", attributes.dig(:metadata, "recipient_organization")
    assert_equal "individual", attributes[:recipient_type]
    assert_equal "RGPNS", attributes[:program_key]
    assert_equal "ON", attributes[:province_code]
    assert_equal "CA", attributes[:country_code]
    assert_equal "https://example.test/2024.csv", attributes[:source_url]
  end

  test "withdraws missing awards only within the independently loaded year" do
    source = Warehouse::Source.create!(
      name: "spending_nserc_awards",
      url: "https://example.test/nserc.json",
      format: "spending_nserc_csv"
    )
    award_1991 = create_award(source, 1991)
    missing_1991 = create_award(source, 1991, external_key: "missing-1991")
    award_2024 = create_award(source, 2024)
    ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/nserc/1991.csv",
      checksum: SecureRandom.hex(32),
      status: :pending
    )

    result = ingestion.spending_loader.load(
      body: StringIO.new(<<~CSV),
        external_id,title,fiscal_year,award_amount
        award-1991,Current 1991 award,1991,1000
      CSV
      withdrawal_scope: { fiscal_year: 1991 }
    )

    assert_equal 1, result.withdrawn
    assert_predicate award_1991.reload, :published?
    assert_predicate missing_1991.reload, :withdrawn?
    assert_predicate award_2024.reload, :published?
  end

  private

  def parsed_attributes(payload)
    source = Struct.new(:url).new("https://www.nserc-crsng.gc.ca/ase-oro/index_eng.asp")
    ingestion = Struct.new(:source).new(source)
    [].tap do |attributes|
      Warehouse::Spending::Scrapers::NsercAwards.new(ingestion).send(:each_attributes, payload) do |value|
        attributes << value
      end
    end
  end

  def create_award(source, fiscal_year, external_key: "award-#{fiscal_year}")
    old = 1.day.ago
    source.spending_awards.create!(
      external_key:,
      award_type: "grant",
      title: "Award #{fiscal_year}",
      fiscal_year:,
      first_seen_at: old,
      last_seen_at: old
    )
  end
end
