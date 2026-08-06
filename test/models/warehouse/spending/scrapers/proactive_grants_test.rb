require "test_helper"

class Warehouse::Spending::Scrapers::ProactiveGrantsTest < ActiveJob::TestCase
  HEADERS = "ref_number,amendment_number,amendment_date,agreement_type,recipient_type,recipient_business_number,recipient_legal_name,recipient_operating_name,research_organization_name,recipient_country,recipient_province,recipient_city,recipient_postal_code,federal_riding_name_en,federal_riding_name_fr,federal_riding_number,prog_name_en,prog_name_fr,prog_purpose_en,prog_purpose_fr,agreement_title_en,agreement_title_fr,agreement_number,agreement_value,foreign_currency_type,foreign_currency_value,agreement_start_date,agreement_end_date,coverage,description_en,description_fr,naics_identifier,expected_results_en,expected_results_fr,additional_information_en,additional_information_fr,owner_org,owner_org_title".split(",")
  VALUES = {
    "ref_number" => "01-2019-2020-Q4- 16727281", "amendment_number" => "0",
    "agreement_type" => "G", "recipient_type" => "academic",
    "recipient_legal_name" => "Canadian Standards Association", "recipient_country" => "CA",
    "recipient_province" => "ON", "recipient_city" => "Toronto",
    "recipient_postal_code" => "M9W 1R3",
    "prog_name_en" => "Advancing Accessibility Standards Research",
    "prog_purpose_en" => "Research program purpose",
    "agreement_title_en" => "Analysis of CSA Group standards to identify accessibility enhancements",
    "agreement_number" => "AGR-1", "agreement_value" => "79365",
    "agreement_start_date" => "2020-03-23", "agreement_end_date" => "2021-02-19",
    "description_en" => "The program funds the project.",
    "expected_results_en" => "Research projects build accessibility standards.",
    "owner_org" => "casdo-ocena",
    "owner_org_title" => "Accessibility Standards Canada | Normes d’accessibilité Canada"
  }.freeze
  GENERATED_CSV = CSV.generate do |csv|
    csv << HEADERS
    csv << HEADERS.map { |header| VALUES[header] }
  end
  # The archived 1 GB source has CRLF after its header and LF after data rows.
  CSV_PAYLOAD = "\uFEFF#{GENERATED_CSV.sub("\n", "\r\n")}"

  setup do
    @source = Warehouse::Source.create!(
      name: "spending_proactive_grants",
      url: "https://example.test/grants.csv",
      format: "csv"
    )
  end

  test "parses the archived mixed-line-ending grant CSV and normalizes the agreement" do
    ingestion = create_ingestion("grants-1")

    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ ingestion ]) do
        result = ingestion.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 1, result.created
      end
    end

    award = Warehouse::SpendingAward.sole
    assert_equal "grant", award.award_type
    assert_equal "Analysis of CSA Group standards to identify accessibility enhancements", award.title
    assert_equal "Accessibility Standards Canada", award.payer_name
    assert_equal "Canadian Standards Association", award.recipient_name
    assert_equal "academic", award.recipient_type
    assert_equal "Advancing Accessibility Standards Research", award.program_name
    assert_equal "AGR-1", award.program_key
    assert_equal 2019, award.fiscal_year
    assert_equal Time.zone.local(2020, 3, 23), award.occurred_at
    assert_equal BigDecimal("79365"), award.amount
    assert_equal "ON", award.province_code
    assert_equal "CA", award.country_code
    assert_equal "complete", ingestion.reload.status
  end

  test "uses amendment number in its stable idempotency key" do
    create_ingestion("grants-2").spending_loader.load(body: CSV_PAYLOAD)

    ingestion = create_ingestion("grants-3")
    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ ingestion ]) do
        result = ingestion.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 1, result.unchanged
      end
    end

    assert_equal 1, Warehouse::SpendingAward.count
  end

  test "stores every amendment but makes only the highest amendment canonical" do
    original = VALUES.merge(
      "amendment_number" => "0",
      "amendment_date" => nil,
      "agreement_end_date" => "2020-10-16"
    )
    amendment = VALUES.merge(
      "amendment_number" => "1",
      "amendment_date" => "2020-10-08",
      "agreement_end_date" => "2021-03-31"
    )

    create_ingestion("grants-amendments").spending_loader.load(
      body: csv_payload(amendment, original)
    )

    assert_equal 2, @source.spending_awards.count
    assert_equal 1, @source.spending_awards.search_indexable.count

    versions = @source.spending_awards.sort_by do |award|
      award.metadata.fetch("amendment_number").to_i
    end
    assert_equal versions.first.canonical_key, versions.second.canonical_key
    assert_not versions.first.is_canonical?
    assert_predicate versions.second, :is_canonical?
    assert_equal "withdrawn", versions.first.search_data.fetch(:state)
    assert_equal "published", versions.second.search_data.fetch(:state)
  end

  private

  def create_ingestion(checksum)
    @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/grants.csv",
      checksum: checksum,
      status: :pending
    )
  end

  def csv_payload(*rows)
    CSV.generate do |csv|
      csv << HEADERS
      rows.each { |row| csv << HEADERS.map { |header| row[header] } }
    end
  end
end
