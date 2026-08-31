require "test_helper"

class Warehouse::FinancialStatementExtraction::StoredHeadlinePipelineTest < ActiveSupport::TestCase
  test "reuses an extracted headline without requiring premature approval" do
    file = Tempfile.new([ "headline", ".pdf" ])
    file.write("source")
    file.flush
    extraction = Struct.new(
      :status, :extractor_version, :asset_sha256, :financial_statement_facts,
      :check_results, :llm_prompt_snapshot, :llm_response_snapshot,
      :language, :statement_basis
    ).new(
      "extracted", Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      Digest::SHA256.file(file.path).hexdigest, [], [], { "prompt" => "headline" }, {},
      "en", "consolidated"
    )
    locator_result = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1, page_texts: { 1 => "statement" }, position_page: 1,
      operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    locator = Struct.new(:result) { def locate = result }.new(locator_result)

    result = Warehouse::FinancialStatementExtraction::StoredHeadlinePipeline.new(
      extraction:, pdf_path: file.path, page_locator: locator
    ).run

    assert_equal "extracted", result.status
    assert_equal "headline", result.prompt
  ensure
    file&.close!
  end

  test "requires explicit opt in to reuse a headline needing review" do
    file = Tempfile.new([ "headline", ".pdf" ])
    file.write("source")
    file.flush
    extraction = Struct.new(
      :status, :extractor_version, :asset_sha256, :financial_statement_facts,
      :check_results, :llm_prompt_snapshot, :llm_response_snapshot,
      :language, :statement_basis
    ).new(
      "needs_review", Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      Digest::SHA256.file(file.path).hexdigest, [], [], { "prompt" => "headline" }, {},
      "en", "consolidated"
    )
    locator_result = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1, page_texts: { 1 => "statement" }, position_page: 1,
      operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    locator = Struct.new(:result) { def locate = result }.new(locator_result)

    assert_raises(ArgumentError) do
      Warehouse::FinancialStatementExtraction::StoredHeadlinePipeline.new(
        extraction:, pdf_path: file.path, page_locator: locator
      ).run
    end
    result = Warehouse::FinancialStatementExtraction::StoredHeadlinePipeline.new(
      extraction:, pdf_path: file.path, page_locator: locator, allow_needs_review: true
    ).run

    assert_equal "needs_review", result.status
  ensure
    file&.close!
  end
end
