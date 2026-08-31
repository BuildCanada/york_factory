require "test_helper"

class Warehouse::FinancialStatementExtraction::PipelineTest < ActiveSupport::TestCase
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
