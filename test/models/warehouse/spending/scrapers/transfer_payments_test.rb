require "test_helper"

class Warehouse::Spending::Scrapers::TransferPaymentsTest < ActiveJob::TestCase
  CSV_PAYLOAD = <<~CSV
    FSCL_YR,MINC,MINE,MINF,DepartmentNumber-Numéro-de-Ministère,DEPT_EN_DESC,DEPT_FR_DESC,RCPNT_CLS_EN_DESC,RCPNT_CLS_FR_DESC,RCPNT_NML_EN_DESC,RCPNT_NML_FR_DESC,CTY_EN_NM,CTY_FR_NM,PROVTER_EN,PROVTER_FR,CNTRY_EN_NM,CNTRY_FR_NM,TOT_CY_XPND_AMT,AGRG_PYMT_AMT
    2023/2024,02,Agriculture and Agri-Food,Agriculture et Agroalimentaire,001,Department of Agriculture and Agri-Food,Ministère de l'Agriculture,Grants to support the Canadian wine industry,Subventions à l'industrie vinicole canadienne,,,,,,,,,78550493,0
    2023/2024,02,Agriculture and Agri-Food,Agriculture et Agroalimentaire,001,Department of Agriculture and Agri-Food,Ministère de l'Agriculture,Grants to support the Canadian wine industry,Subventions à l'industrie vinicole canadienne,0831517 BC Ltd,0831517 BC Ltd,Penticton,Penticton,British Columbia,Colombie-Britannique,Canada,Canada,0,129579
  CSV

  setup do
    @source = Warehouse::Source.create!(
      name: "spending_transfer_payments",
      url: "https://example.test/transfers.csv",
      format: "csv"
    )
  end

  test "normalizes aggregate program totals and recipient payments" do
    ingestion = create_ingestion("transfers-1")

    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ ingestion ]) do
        result = ingestion.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 2, result.created
      end
    end

    aggregate = Warehouse::SpendingAward.find_by!(is_aggregated: true)
    assert_equal "transfer_payment", aggregate.award_type
    assert_equal "Multiple recipients", aggregate.recipient_name
    assert_equal BigDecimal("78550493"), aggregate.amount
    assert_equal 2023, aggregate.fiscal_year
    assert_equal Time.zone.local(2023, 4, 1), aggregate.occurred_at

    payment = Warehouse::SpendingAward.find_by!(is_aggregated: false)
    assert_equal "0831517 BC Ltd", payment.recipient_name
    assert_equal "grantee", payment.recipient_type
    assert_equal BigDecimal("129579"), payment.amount
    assert_equal "BC", payment.province_code
    assert_equal "CA", payment.country_code
    assert_equal "001", payment.program_key
    assert_equal "Penticton", payment.metadata.fetch("city")
    assert_equal "complete", ingestion.reload.status
  end

  test "deduplicates identical disclosed payment rows across ingestions" do
    create_ingestion("transfers-2").spending_loader.load(body: CSV_PAYLOAD)

    ingestion = create_ingestion("transfers-3")
    assert_no_enqueued_jobs only: Search::SyncJob do
      assert_enqueued_with(job: Warehouse::SyncSpendingIngestionJob, args: [ ingestion ]) do
        result = ingestion.spending_loader.load(body: CSV_PAYLOAD)
        assert_equal 2, result.unchanged
      end
    end

    assert_equal 2, Warehouse::SpendingAward.count
  end

  test "normalizes the official historical and current Public Accounts headers" do
    payload = <<~CSV
      Fscl-yr_Ex-fin,Min-code,Min-portfolio_Portefeuille-min_eng,Dept-nbr_No-min,Dept-name_Nom-min_eng,Rcpt-class_Cat-bnfcrs_eng,Rcpt-nm-locn_Nm-lieu-bnfcrs_eng,City_Ville_eng,Prov-Terr_eng,Country_Pays_eng,Xpnd-current-yr_Dep-ex-courant,Aggregate-payments_Versements-totalisant
      2024/2025,02,Agriculture and Agri-Food,001,Department of Agriculture and Agri-Food,International Collaboration,CABI Publishing,Wallingford,,United Kingdom,0,346031
    CSV

    result = create_ingestion("transfers-official-headers").spending_loader.load(body: payload)

    assert_equal 1, result.created
    payment = Warehouse::SpendingAward.sole
    assert_equal 2024, payment.fiscal_year
    assert_equal "Department of Agriculture and Agri-Food", payment.payer_name
    assert_equal "International Collaboration", payment.program_name
    assert_equal "CABI Publishing", payment.recipient_name
    assert_equal BigDecimal("346031"), payment.amount
    assert_equal "Wallingford", payment.metadata.fetch("city")
    assert_equal Warehouse::Spending::Scrapers::TransferPayments::SOURCE_URL, payment.source_url
  end

  test "normalizes the reduced 2003 Public Accounts schema" do
    payload = <<~CSV
      Fscl-yr_Ex-fin,Min-portfolio_Portefeuille-min_eng,Dept-name_Nom-min_eng,Rcpt-class_Cat-bnfcrs_eng,Rcpt-nm-locn_Nm-lieu-bnfcrs_eng,Aggregate-payments_Versements-totalisant
      2002/2003,Agriculture and Agri-Food,Agriculture and Agri-Food,Rural Development,"Agriculture Adaptation Council Guelph Ont",8463741
    CSV

    result = create_ingestion("transfers-2003-headers").spending_loader.load(body: payload)

    assert_equal 1, result.created
    payment = Warehouse::SpendingAward.sole
    assert_equal 2002, payment.fiscal_year
    assert_equal "Agriculture and Agri-Food", payment.payer_name
    assert_equal "Agriculture Adaptation Council Guelph Ont", payment.recipient_name
    assert_equal BigDecimal("8463741"), payment.amount
  end

  private

  def create_ingestion(checksum)
    @source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: "raw/test/transfers.csv",
      checksum: checksum,
      status: :pending
    )
  end
end
