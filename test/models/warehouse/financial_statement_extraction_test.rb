require "test_helper"

class Warehouse::FinancialStatementExtractionTest < ActiveSupport::TestCase
  test "reviewed extractions cannot be rerun in place" do
    extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_canonical_id: "ca/on/example",
      document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64,
      fiscal_year_end: Date.new(2025, 12, 31),
      extractor_version: "test-v1",
      status: "extracted"
    )
    extraction.approve!(reviewer: "reviewer")

    error = assert_raises(ArgumentError) do
      extraction.extractor.extract(pdf_path: "missing.pdf", institution_name: "Example")
    end
    assert_includes error.message, "immutable"
    assert_equal "approved", extraction.reload.status
  end
end
