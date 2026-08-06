require "test_helper"

class Warehouse::Spending::Scrapers::AggregatedContractsTest < ActiveJob::TestCase
  CSV_PAYLOAD = <<~CSV
    year,contract_goods_number_of,contracts_goods_original_value,contracts_goods_amendment_value,contract_service_number_of,contracts_service_original_value,contracts_service_amendment_value,contract_construction_number_of,contracts_construction_original_value,contracts_construction_amendment_value,acquisition_card_transactions_number_of,acquisition_card_transactions_total_value,owner_org,owner_org_title
    2017,34,137159.94,7247.08,211,435738.75,50534.44,0,0,0,3717,1756145.25,atssc-scdata,Administrative Tribunals Support Service of Canada | Service canadien d'appui aux tribunaux administratifs
  CSV

  setup do
    @source = Warehouse::Source.create!(
      name: "spending_aggregated_contracts",
      url: "https://example.test/contracts-under-10k.csv",
      format: "csv"
    )
  end

  test "normalizes every spending component in aggregated contracts" do
    ingestion = create_ingestion("aggregates-1")

    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ ingestion ]) do
        result = ingestion.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 1, result.created
      end
    end

    award = Warehouse::SpendingAward.sole
    assert_equal "contract", award.award_type
    assert_equal "Administrative Tribunals Support Service of Canada", award.payer_name
    assert_equal "Multiple recipients", award.recipient_name
    assert_predicate award, :is_aggregated?
    assert_equal 2017, award.fiscal_year
    assert_equal Time.zone.local(2017, 4, 1), award.occurred_at
    assert_equal BigDecimal("2386825.46"), award.amount
    assert_equal 3717, award.metadata.fetch("acquisition_card_transactions_number_of")
    assert_includes award.description, "Goods: 144407.02"
    assert_equal "complete", ingestion.reload.status
  end

  test "upserts the same organization-year without duplicating it" do
    create_ingestion("aggregates-2").spending_loader.load(body: CSV_PAYLOAD)

    ingestion = create_ingestion("aggregates-3")
    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ ingestion ]) do
        result = ingestion.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 1, result.unchanged
      end
    end

    assert_equal 1, Warehouse::SpendingAward.count
  end

  private

  def create_ingestion(checksum)
    @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/contracts-under-10k.csv",
      checksum: checksum,
      status: :pending
    )
  end
end
