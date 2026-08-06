require "test_helper"

class Warehouse::Spending::Scrapers::ProactiveContractsTest < ActiveJob::TestCase
  HEADERS = "reference_number,procurement_id,vendor_name,vendor_postal_code,buyer_name,contract_date,economic_object_code,description_en,description_fr,contract_period_start,delivery_date,contract_value,original_value,amendment_value,comments_en,comments_fr,additional_comments_en,additional_comments_fr,agreement_type_code,trade_agreement,land_claims,commodity_type,commodity_code,country_of_vendor,solicitation_procedure,limited_tendering_reason,trade_agreement_exceptions,indigenous_business,indigenous_business_excluding_psib,intellectual_property,potential_commercial_exploitation,former_public_servant,contracting_entity,standing_offer_number,instrument_type,ministers_office,number_of_bids,article_6_exceptions,award_criteria,socioeconomic_indicator,reporting_period,owner_org,owner_org_title".split(",")
  VALUES = {
    "reference_number" => "C-2019-2020-Q4-1", "procurement_id" => "P2000002",
    "vendor_name" => "Simzer Design Inc.", "vendor_postal_code" => "K1A 0A9",
    "buyer_name" => "Buyer", "contract_date" => "2020-02-26",
    "economic_object_code" => "0351", "description_en" => "Communications professional services",
    "description_fr" => "Services professionnels", "contract_period_start" => "2019-11-15",
    "delivery_date" => "2020-05-30", "contract_value" => "38900.25",
    "original_value" => "15255.00", "amendment_value" => "23645.25",
    "comments_en" => "Increase contract by $23,645", "commodity_type" => "S",
    "commodity_code" => "T005", "country_of_vendor" => "CA",
    "reporting_period" => "2019-2020-Q4", "owner_org" => "casdo-ocena",
    "owner_org_title" => "Accessibility Standards Canada | Normes d'accessibilité Canada"
  }.freeze
  CSV_PAYLOAD = CSV.generate do |csv|
    csv << HEADERS
    csv << HEADERS.map { |header| VALUES[header] }
  end

  setup do
    @payer_organization = Warehouse::Organization.create!(canonical_name: "Accessibility Standards Canada")
    @source = Warehouse::Source.create!(
      name: "spending_proactive_contracts",
      url: "https://example.test/contracts.csv",
      format: "csv"
    )
  end

  test "normalizes and loads proactive contracts into search-owned awards" do
    ingestion = create_ingestion("contracts-1")

    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ ingestion ]) do
        result = ingestion.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 1, result.created
      end
    end

    award = Warehouse::SpendingAward.sole
    assert_equal "contract", award.award_type
    assert_equal "Communications professional services", award.title
    assert_equal "Accessibility Standards Canada", award.payer_name
    assert_equal @payer_organization, award.payer_organization
    assert_equal "Simzer Design Inc.", award.recipient_name
    assert_equal "vendor", award.recipient_type
    assert_equal 2019, award.fiscal_year
    assert_equal Time.zone.local(2020, 2, 26), award.occurred_at
    assert_equal BigDecimal("38900.25"), award.amount
    assert_equal "ON", award.province_code
    assert_equal "CA", award.country_code
    assert_equal "P2000002", award.metadata.fetch("procurement_id")
    assert_equal "complete", ingestion.reload.status
  end

  test "uses a stable source key and queues one resumable ingestion sync" do
    first = create_ingestion("contracts-2")
    first.spending_loader.load(body: CSV_PAYLOAD)
    award = Warehouse::SpendingAward.sole
    external_key = award.external_key

    second = create_ingestion("contracts-3")
    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ second ]) do
        result = second.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 1, result.unchanged
      end
    end

    assert_equal 1, Warehouse::SpendingAward.count
    assert_equal external_key, award.reload.external_key
    assert_equal second, award.raw_ingestion
  end

  test "rejects an empty dataset without withdrawing stored contracts" do
    existing_ingestion = create_ingestion("contracts-before-empty")
    existing_ingestion.spending_loader.load(body: CSV_PAYLOAD)
    empty_ingestion = create_ingestion("contracts-empty")
    empty_payload = CSV.generate { |csv| csv << HEADERS }

    error = assert_raises(RuntimeError) do
      empty_ingestion.spending_loader.load(body: empty_payload)
    end

    assert_match(/contained no records/, error.message)
    assert_predicate Warehouse::SpendingAward.sole, :published?
    assert_predicate empty_ingestion.reload, :failed?
  end

  test "stores every amendment but makes only the latest disclosure canonical" do
    original = VALUES.merge(
      "reference_number" => "C-2019-2020-Q1-00002",
      "reporting_period" => "2019-2020-Q1",
      "contract_value" => "79100.00",
      "original_value" => "79100.00",
      "amendment_value" => "0.00",
      "instrument_type" => "C"
    )
    amendment = VALUES.merge(
      "reference_number" => "C-2019-2020-Q4-00004",
      "reporting_period" => "2019-2020-Q4",
      "contract_value" => "104412.00",
      "original_value" => "79100.00",
      "amendment_value" => "25312.00",
      "instrument_type" => "A"
    )

    create_ingestion("contracts-amendments").spending_loader.load(
      body: csv_payload(amendment, original)
    )

    assert_equal 2, @source.spending_awards.count
    assert_equal 1, @source.spending_awards.search_indexable.count

    versions = @source.spending_awards.order(:amount)
    assert_equal versions.first.canonical_key, versions.second.canonical_key
    assert_not versions.first.is_canonical?
    assert_predicate versions.second, :is_canonical?
    assert_equal BigDecimal("104412.00"), versions.second.amount
    assert_equal "withdrawn", versions.first.search_data.fetch(:state)
    assert_equal "published", versions.second.search_data.fetch(:state)
  end

  test "does not combine unrelated contracts when procurement id is missing" do
    first_contract = VALUES.merge(
      "reference_number" => "C-2025-Q1-1", "procurement_id" => nil
    )
    second_contract = VALUES.merge(
      "reference_number" => "C-2025-Q1-2", "procurement_id" => nil
    )

    create_ingestion("contracts-no-procurement-id").spending_loader.load(
      body: csv_payload(first_contract, second_contract)
    )

    assert_equal 2, @source.spending_awards.search_indexable.count
    assert_equal 2, @source.spending_awards.distinct.count(:canonical_key)
  end

  test "does not combine unrelated contracts with generic procurement ids" do
    null_contract = VALUES.merge(
      "reference_number" => "C-2025-Q1-NULL", "procurement_id" => "NULL"
    )
    acquisition_card_contract = VALUES.merge(
      "reference_number" => "C-2025-Q1-CARD", "procurement_id" => "Acquisition Card"
    )

    create_ingestion("contracts-generic-procurement-ids").spending_loader.load(
      body: csv_payload(null_contract, acquisition_card_contract)
    )

    assert_equal 2, @source.spending_awards.search_indexable.count
    assert_equal 2, @source.spending_awards.distinct.count(:canonical_key)
  end

  private

  def create_ingestion(checksum)
    @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/contracts.csv",
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
