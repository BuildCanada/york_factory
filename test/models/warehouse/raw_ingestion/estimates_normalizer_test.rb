require "test_helper"

class Warehouse::RawIngestion::EstimatesNormalizerTest < ActiveSupport::TestCase
  setup do
    @source = Warehouse::Source.create!(name: "estimates_test", url: "https://example.com/test.csv", format: "csv")
    @ingestion = Warehouse::RawIngestion.create!(
      source: @source,
      fetched_at: Time.current,
      raw_file_path: "raw/test/estimates.csv",
      checksum: "est123",
      status: :pending
    )

    # Pre-create orgs that would come from InfoBase loader
    @org = Warehouse::Organization.create!(canonical_name: "Atlantic Canada Opportunities Agency", org_id_infobase: 10)
    @org.organization_aliases.create!(alias_name: "Atlantic Canada Opportunities Agency")
  end

  test "normalizes Main Estimates CSV" do
    csv = <<~CSV
      Organization,Vote,Description,2023-24 Expenditures,2024-25 Main Estimates,2024-25 Estimates To Date,2025-26 Main Estimates
      Atlantic Canada Opportunities Agency,   1,Operating expenditures,72151912,70390767,70718618,70274559
    CSV

    @ingestion.estimates_normalizer.normalize(csv_content: csv)

    # Should create fiscal_authorities for the Main Estimates columns
    assert Warehouse::FiscalAuthority.exists?(fiscal_year: "2025-26", document_type: "main")
    assert Warehouse::FiscalAuthority.exists?(fiscal_year: "2024-25", document_type: "main")

    fa = Warehouse::FiscalAuthority.find_by(fiscal_year: "2025-26")
    assert_equal @org.id, fa.organization_id
    assert_equal "operating", fa.vote_type
    assert_equal 70_274_559, fa.amount.to_i
  end

  test "handles statutory votes" do
    csv = <<~CSV
      Organization,Vote,Description,2025-26 Main Estimates
      Atlantic Canada Opportunities Agency,S,Contributions to employee benefit plans,9497319
    CSV

    @ingestion.estimates_normalizer.normalize(csv_content: csv)

    fa = Warehouse::FiscalAuthority.first
    assert_equal "statutory", fa.vote_type
    assert_equal "S", fa.vote_number
  end

  test "skips unresolvable organizations gracefully" do
    csv = <<~CSV
      Organization,Vote,Description,2025-26 Main Estimates
      Completely Unknown Agency,   1,Operating,100000
    CSV

    @ingestion.estimates_normalizer.normalize(csv_content: csv)

    # Should be partial (skipped row) or complete if it simply couldn't resolve
    assert_includes [ "partial", "complete" ], @ingestion.reload.status
  end

  test "strips formatting from amounts" do
    csv = <<~CSV
      Organization,Vote,Description,2025-26 Main Estimates
      Atlantic Canada Opportunities Agency,   1,Operating,"1,234,567"
    CSV

    @ingestion.estimates_normalizer.normalize(csv_content: csv)

    fa = Warehouse::FiscalAuthority.first
    assert_equal 1_234_567, fa.amount.to_i
  end

  test "marks ingestion as complete when all rows succeed" do
    csv = <<~CSV
      Organization,Vote,Description,2025-26 Main Estimates
      Atlantic Canada Opportunities Agency,   1,Operating,100000
    CSV

    @ingestion.estimates_normalizer.normalize(csv_content: csv)

    assert_equal "complete", @ingestion.reload.status
  end

  test "extracts fiscal year from column headers" do
    csv = <<~CSV
      Organization,Vote,Description,2025-26 Main Estimates
      Atlantic Canada Opportunities Agency,   1,Operating,100000
    CSV

    @ingestion.estimates_normalizer.normalize(csv_content: csv)

    fa = Warehouse::FiscalAuthority.first
    assert_equal "2025-26", fa.fiscal_year
    assert_equal "main", fa.document_type
  end
end
