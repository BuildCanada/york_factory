require "test_helper"

class Warehouse::FinancialStatementExtraction::PipelineTest < ActiveSupport::TestCase
  test "limits headline extraction to primary statements and a relevant supporting schedule" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 19,
      page_texts: {
        6 => "Statement of Operations 2010 Revenues Expenses",
        7 => "Statement of Financial Position 2010",
        8 => "Statement of Cash Flows 2010 revenues expenses",
        19 => "Schedule 3 Revenue and Expenditures 2010\nRevenues 3,000 Expenses 2,000"
      },
      position_page: 7, operations_page: 6, candidate_pages: [ 5, 6, 7, 8 ], ocr_pages: []
    )
    pipeline = Warehouse::FinancialStatementExtraction::Pipeline.allocate
    pipeline.instance_variable_set(:@fiscal_year_end, Date.new(2010, 12, 31))

    limited = pipeline.send(:primary_statement_locator, locator)

    assert_equal [ 6, 7, 19 ], limited.candidate_pages
  end

  test "does not manufacture a year that was absent from the model's cited heading" do
    normalized = Warehouse::FinancialStatementExtraction::Pipeline.normalize_column_year(
      "Actual", fiscal_year: 2024, page_text: "2024 2024 2023\nBudget Actual Actual"
    )

    assert_equal "Actual", normalized
  end

  test "prompt defines source-backed single-component totals and explicit provenance" do
    pipeline = Warehouse::FinancialStatementExtraction::Pipeline.allocate
    pipeline.instance_variable_set(:@institution_name, "Example")
    pipeline.instance_variable_set(:@institution_canonical_id, "ca/nl/example")
    pipeline.instance_variable_set(:@document_canonical_id, "ca/nl/example/documents/financial-statements/2025/general")
    pipeline.instance_variable_set(:@fiscal_year_end, Date.new(2025, 12, 31))
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => "Position", 2 => "Operations" },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: []
    )

    prompt = pipeline.send(:build_prompt, located)

    assert_includes prompt, "exactly one printed component"
    assert_includes prompt, "set the matching *_single_component boolean true"
    assert_includes prompt, "confidence no higher than 0.90"
  end

  test "requires a flagged single-component fact and caps its confidence" do
    pipeline = Warehouse::FinancialStatementExtraction::Pipeline.allocate
    pipeline.instance_variable_set(:@fiscal_year_end, Date.new(2025, 12, 31))
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1, page_texts: { 1 => "Position" }, position_page: 1,
      operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    response = {
      "language" => "en", "statement_basis" => "consolidated", "fiscal_year" => 2025,
      "total_financial_assets_single_component" => true,
      "facts" => [ fact("total_liabilities", "Liabilities", "1", 1) ]
    }

    error = assert_raises(Warehouse::FinancialStatementExtraction::Pipeline::ResponseError) do
      pipeline.send(:validate_response!, response, located)
    end
    assert_includes error.message, "lacks total_financial_assets"

    response["facts"] = [ fact("total_financial_assets", "Accounts receivable", "1", 1) ]
    error = assert_raises(Warehouse::FinancialStatementExtraction::Pipeline::ResponseError) do
      pipeline.send(:validate_response!, response, located)
    end
    assert_includes error.message, "confidence exceeds 0.90"
  end

  Locator = Struct.new(:result) do
    def locate = result
    def with_excerpt(*) = yield(Pathname("excerpt.pdf"))
  end

  test "derives signed whole-dollar values from cited text instead of asking the model to normalize" do
    Dir.mktmpdir do |directory|
      pdf = Pathname(directory).join("statement.pdf")
      pdf.binwrite("%PDF-test")
      sha256 = Digest::SHA256.file(pdf).hexdigest
      response = {
        "language" => "en", "statement_basis" => "consolidated", "fiscal_year" => 2025,
        "remeasurement_present" => true, "rollforward_adjustment_present" => false,
        "operations_adjustment_present" => false,
        "facts" => [
          fact("total_financial_assets", "Financial assets", "17,301", 1),
          fact("total_liabilities", "Liabilities", "26,903", 1),
          fact("net_financial_assets", "Net debt", "9,602", 1),
          fact("total_non_financial_assets", "Non-financial assets", "43,304", 1),
          fact("accumulated_surplus", "Accumulated surplus", "32,730", 1),
          fact("total_revenue", "Revenue", "16,325", 2, statement: "operations"),
          fact("total_expenses", "Expenses", "15,075", 2, statement: "operations"),
          fact("annual_surplus", "Annual surplus", "1,250", 2, statement: "operations")
        ]
      }
      pages = {
        1 => response.fetch("facts").first(5).map { |item| "#{item['raw_label']} #{item['raw_text']}" }.join("\n") + "\nAccumulated remeasurement gains 972",
        2 => response.fetch("facts").drop(5).map { |item| "#{item['raw_label']} #{item['raw_text']}" }.join("\n")
      }
      located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
        page_count: 2, page_texts: pages, position_page: 1, operations_page: 2,
        candidate_pages: [ 1, 2 ], ocr_pages: []
      )

      result = Warehouse::FinancialStatementExtraction::Pipeline.new(
        pdf_path: pdf, institution_canonical_id: "ca/on/example", institution_name: "Example",
        document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
        asset_sha256: sha256, fiscal_year_end: Date.new(2025, 12, 31),
        page_locator: Locator.new(located), llm_client: ->(**) { response }
      ).run

      assert_equal "extracted", result.status
      assert_equal BigDecimal("1250000000"), result.facts.index_by { |item| item[:concept] }
        .fetch("annual_surplus").fetch(:value)
      assert_equal BigDecimal("-9602000000"), result.facts.index_by { |item| item[:concept] }
        .fetch("net_financial_assets").fetch(:value)
      assert_equal "pass", result.checks.find { |check| check[:id] == "source_identity" }.fetch(:status)

      stale_response = response.deep_dup
      stale_response.fetch("facts").each { _1["excerpt_page"] += 5 }
      source_pages = result.facts.to_h { [ _1.fetch(:concept), _1.fetch(:source_page) ] }
      revalidated = Warehouse::FinancialStatementExtraction::Pipeline.new(
        pdf_path: pdf, institution_canonical_id: "ca/on/example", institution_name: "Example",
        document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
        asset_sha256: sha256, fiscal_year_end: Date.new(2025, 12, 31),
        page_locator: Locator.new(located), llm_client: ->(**) { raise "model must not be called" }
      ).revalidate(response: stale_response, source_pages:)
      assert_equal "extracted", revalidated.status
    end
  end

  private

  def fact(concept, label, text, page, statement: "financial_position")
    {
      "concept" => concept, "statement" => statement, "raw_label" => label, "raw_text" => text,
      "scale" => 1_000_000, "excerpt_page" => page, "column_year" => "Actual 2025", "confidence" => 0.99
    }
  end
end
