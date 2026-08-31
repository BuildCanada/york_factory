require "test_helper"

class Warehouse::FinancialStatementExtraction::SaskatchewanFormPipelineTest < ActiveSupport::TestCase
  class TableOcrLocator
    attr_reader :calls

    def initialize(result, table_texts)
      @result = result
      @table_texts = table_texts
      @calls = []
    end

    def locate = @result

    def ocr_table_page(page)
      calls << page
      @table_texts.fetch(page)
    end
  end

  test "reads the actual column without treating label hyphens as blank cells" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2022, kind: :operations)
      2022 Budget 2022 2021
      REVENUES (unaudited)
      Taxes and Other Unconditional Revenue (Schedule 1) 180,880 211,152 185,902
      Tangible Capital Asset Sales - Gain (Schedule 4, 5) - 122 400
      Environmental Services 30.380 32,228 30.347
      Protective Services 13,230 1 1,375 13,319
      Total Revenues 180,880 211,274 186,302
      EXPENSES
      General Government Services (Schedule 3) 62,280 45,222 55,107
      Total Expenses 62,280 45,222 55,107
      Annual Surplus = 97,365 55,340
    TEXT

    assert_equal "211,152", page.lines.find { _1[:label].start_with?("Taxes") }.fetch(:current)
    capital_sale = page.lines.find { _1[:label].start_with?("Tangible") }
    assert_equal "Tangible Capital Asset Sales - Gain (Schedule 4, 5)", capital_sale.fetch(:label)
    assert_equal "122", capital_sale.fetch(:current)
    assert_equal "32,228", page.lines.find { _1[:label].start_with?("Environmental") }.fetch(:current)
    assert_equal "1 1,375", page.lines.find { _1[:label].start_with?("Protective") }.fetch(:current)
    assert_equal "97,365", page.lines.find { _1[:label].start_with?("Annual Surplus") }.fetch(:current)
    assert_equal 4, page.between(/\AREVENUES/, /\ATotal Revenues/).length
  end

  test "drops only an unambiguous trailing OCR null column" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2025, kind: :position)
      2025 2024
      ACCUMULATED SURPLUS 15,056,773 14,004,009 -
      Legitimate prior-year null 100 -
      Adjustment 2025 100 -
      Ambiguous extra null 100 - -
    TEXT

    assert_equal "15,056,773", page.lines.find { _1[:label].start_with?("ACCUMULATED") }.fetch(:current)
    assert_equal "100", page.lines.find { _1[:label].start_with?("Legitimate") }.fetch(:current)
    assert_equal "100", page.lines.find { _1[:label].start_with?("Adjustment") }.fetch(:current)
    assert_equal "-", page.lines.find { _1[:label].start_with?("Ambiguous") }.fetch(:current)
  end

  test "recognizes surplus of revenues over expenditures" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2025, kind: :operations)
      2025 Budget 2025 2024
      Surplus (deficit) of revenues over expenditures 10 20 15
    TEXT
    row = page.lines.sole

    assert_match Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::ANNUAL_SURPLUS_PATTERN,
      row.fetch(:label)
    assert_equal "20", row.fetch(:current)
  end

  test "trims only an adjacent truncated prior-year OCR fragment" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2025, kind: :operations)
      2025 Budget 2025 2024
      Comma-truncated prior 100 200 222,23
      Dot-truncated prior 100 200 1.641,28
      Genuine small prior 100 200 23
      Note reference (Note 13) 100 200 23
      Truncated current 100 2,00 300
    TEXT

    assert_equal "200", page.lines.find { _1[:label].start_with?("Comma") }.fetch(:current)
    assert_equal "200", page.lines.find { _1[:label].start_with?("Dot") }.fetch(:current)
    assert_equal "200", page.lines.find { _1[:label].start_with?("Genuine") }.fetch(:current)
    assert_equal "200", page.lines.find { _1[:label].start_with?("Note") }.fetch(:current)
    assert_equal "00", page.lines.find { _1[:label].start_with?("Truncated current") }.fetch(:current)
  end

  test "keeps unlabeled OCR total rows available for form-level association" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2022, kind: :position)
      2022
      2021
      Total Financial Assets
      Cash 300,000 290,000
      446,415 432,511
    TEXT

    total = page.fetch(/\ATotal Financial Assets/)
    assert_nil total.fetch(:current)
    assert_equal "446,415", page.lines.find { _1[:label].blank? }.fetch(:current)
  end

  test "does not mistake an individual liability for total liabilities" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2023, kind: :position)
      2023 2022
      FINANCIAL LIABILITIES
      Liability for Contaminated Sites (Note 13) - -
      Total Liabilities 64,241 73,211
    TEXT

    total = page.fetch(Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::FACT_LABELS.fetch(:total_liabilities))

    assert_equal "Total Liabilities", total.fetch(:label)
    assert_equal "64,241", total.fetch(:current)
  end

  test "associates bounded unlabeled position totals after multiple component rows" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2023, kind: :position)
      2023 2022
      FINANCIAL ASSETS
      Cash 100 90
      Investments 200 180
      Receivables 50 50
      ____ 350 320
      LIABILITIES
      Accounts payable 100 90
      Long-term debt 50 50
      150 140
      NET FINANCIAL ASSETS 200 180
      NON-FINANCIAL ASSETS
      Tangible capital assets 500 480
      Inventories 20 20
      520 500
      ACCUMULATED SURPLUS 720 680
    TEXT
    pipeline = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.allocate

    financial_assets = pipeline.send(:position_total, page, :total_financial_assets)
    liabilities = pipeline.send(:position_total, page, :total_liabilities)
    non_financial_assets = pipeline.send(:position_total, page, :total_non_financial_assets)

    assert_equal "350", financial_assets.fetch(:current)
    assert_equal "150", liabilities.fetch(:current)
    assert_equal "520", non_financial_assets.fetch(:current)
    assert_equal BigDecimal("0.95"), financial_assets.fetch(:extraction_confidence)
  end

  test "uses a sole non-financial asset component as the bounded total" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2023, kind: :position)
      2023 2022
      NON-FINANCIAL ASSETS
      Tangible capital assets 520 500
      ACCUMULATED SURPLUS 720 680
    TEXT
    pipeline = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.allocate

    total = pipeline.send(:position_total, page, :total_non_financial_assets)

    assert_equal "Tangible capital assets", total.fetch(:label)
    assert_equal "520", total.fetch(:current)
    assert_equal BigDecimal("0.90"), total.fetch(:extraction_confidence)
  end

  test "rejects an unlabeled position value when the section lacks multiple labeled components" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2023, kind: :position)
      2023 2022
      FINANCIAL ASSETS
      Cash 100 90
      100 90
      LIABILITIES
    TEXT
    pipeline = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.allocate

    assert_nil pipeline.send(:position_total, page, :total_financial_assets)
  end

  test "infers omitted standardized form headers and joins wrapped annual surplus labels" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2018, kind: :operations)
      MUNICIPALITY OF EXAMPLE
      Statement of Operations
      Year Ended December 31, 2018

      REVENUES
      Taxes (Schedule 1) 100,000 110,000 90,000
      Fees and charges (Schedule 4) 20,000 25,000 15,000
      Other revenue 5,000 6,000 4,000
      125,000 141,000 109,000

      EXPENSES
      General government (Schedule 3) 100,000 100,000 90,000
      Transportation 10,000 10,000 9,000
      Recreation 5,000 5,000 4,000
      115,000 115,000 103,000

      EXCESS (DEFICIENCY) OF REVENUES
        OVER EXPENSES BEFORE OTHER
        CAPITAL CONTRIBUTIONS 10,000 26,000 6,000
      Capital grants 2,000 3,000 1,000
      EXCESS (DEFICIENCY) OF REVENUES OVER
        EXPENSES 12,000 29,000 7,000
    TEXT

    taxes = page.lines.find { _1[:label].start_with?("Taxes") }
    annual_rows = page.lines.select do |row|
      row[:label].match?(Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::ANNUAL_SURPLUS_PATTERN)
    end

    assert_equal "110,000", taxes.fetch(:current)
    assert_equal 2, annual_rows.length
    assert_equal "29,000", annual_rows.last.fetch(:current)
    assert_equal "EXCESS (DEFICIENCY) OF REVENUES OVER EXPENSES", annual_rows.last.fetch(:label)
  end

  test "joins shortfall surplus labels and keeps the final row after before-other subtotal" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2018, kind: :operations)
      2018 Budget 2018 2017
      REVENUE
      Taxes 90 100 80
      Total Revenue 90 100 80
      EXPENSES
      Services 80 90 70
      Total Expenses 80 90 70
      EXCESS (SHORTFALL) OF REVENUE OVER
       EXPENSES - BEFORE OTHER 10 10 10
      Capital grants - 20 -
      EXCESS (SHORTFALL) OF REVENUE OVER
       EXPENSES 10 30 10
    TEXT

    rows = page.lines.select do |row|
      row[:label].match?(Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::ANNUAL_SURPLUS_PATTERN)
    end

    assert_equal 2, rows.length
    assert_equal "10", rows.first.fetch(:current)
    assert_equal "30", rows.last.fetch(:current)
    assert_equal "EXCESS (SHORTFALL) OF REVENUE OVER EXPENSES", rows.last.fetch(:label)
  end

  test "joins a wrapped position total to an unlabeled numeric row" do
    page = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::EnglishPage.new(<<~TEXT, fiscal_year: 2023, kind: :position)
      MUNICIPALITY OF EXAMPLE
      Statement of Financial Position
      As at December 31, 2023

      Cash 300,000 290,000
      Investments 100,000 90,000
      Receivables 40,000 35,000
      Total Financial Assets
      440,000 415,000
    TEXT

    total = page.fetch(Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::FACT_LABELS.fetch(:total_financial_assets))

    assert_equal "Total Financial Assets", total.fetch(:label)
    assert_equal "440,000", total.fetch(:current)
  end

  test "handles an optional opening surplus without duplicating capital contributions" do
    source = Tempfile.new([ "municipal-statement", ".pdf" ])
    source.write("source")
    source.close
    sha = Digest::SHA256.file(source.path).hexdigest
    position = <<~TEXT
      2025 2024
      Total Financial Assets 100 90
      LIABILITIES
      Total Liabi lities
      - -
      60 50
      NET FINANCIAL ASSETS 40 40
      Total Non-Financial Assets 160 140
      ACCUMULATED SURPLUS 200 180
    TEXT
    operations = <<~TEXT
      2025 Budget 2025 2024
      REVENUES
      Taxes 90 90 80
      Provincial Capital Grants and Contributions 10 10 -
      100 100 80
      Total Revenues - - -
      EXPENSES
      General Government 80 80 60
      Total Expenses 80 80 60
      Annual Surplus 20 20 20
      Annual Surplus - - -
    TEXT
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => position, 2 => operations },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: []
    )
    locator = Struct.new(:result) { def locate = result }.new(located)

    result = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: source.path, institution_canonical_id: "ca/sk/example",
      document_canonical_id: "ca/sk/example/documents/financial-statements/2025/general",
      asset_sha256: sha, fiscal_year_end: Date.new(2025, 12, 31), page_locator: locator
    ).run

    capital_rows = result.line_items.select { _1[:label].include?("Capital Grants") }
    assert_equal "extracted", result.status
    assert_equal 1, capital_rows.length
    assert_equal 60, result.facts.find { _1[:concept] == "total_liabilities" }.fetch(:value)
    refute result.facts.any? { _1[:concept] == "opening_accumulated_surplus" }
    assert result.checks.find { _1[:id] == "line_sum:revenue" && _1[:status] == "pass" }
    assert result.checks.find { _1[:id] == "surplus_rollforward" && _1[:status] == "skip" }
  ensure
    source&.unlink
  end

  test "bounds expense line items by annual surplus when the printed total is unlabeled" do
    source = Tempfile.new([ "municipal-statement", ".pdf" ])
    source.write("source")
    source.close
    sha = Digest::SHA256.file(source.path).hexdigest
    position = <<~TEXT
      2017 2016
      Total Financial Assets 100 90
      Total Liabilities 60 50
      NET FINANCIAL ASSETS 40 40
      Total Non-Financial Assets 170 140
      ACCUMULATED SURPLUS 210 180
    TEXT
    operations = <<~TEXT
      2017 Budget 2017 2016
      REVENUE
      Taxes 100 100 90
      100 100 90
      EXPENSE
      Services 80 80 70
      80 80 70
      EXCESS (SHORTFALL) OF REVENUE OVER EXPENSES BEFORE OTHER 20 20 20
      OTHER
      Government transfers for capital 10 10 10
      EXCESS (SHORTFALL) OF REVENUE OVER EXPENSES 30 30 30
      ACCUMULATED SURPLUS, BEGINNING OF YEAR 180 180 160
      ACCUMULATED SURPLUS, END OF YEAR 210 210 180
    TEXT
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => position, 2 => operations },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: []
    )
    locator = Struct.new(:result) do
      def locate = result
      def ocr_table_page(page) = result.page_texts.fetch(page)
    end.new(located)

    result = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: source.path, institution_canonical_id: "ca/ab/example",
      document_canonical_id: "ca/ab/example/documents/financial-statements/2017/general",
      asset_sha256: sha, fiscal_year_end: Date.new(2017, 12, 31), page_locator: locator
    ).run

    assert_equal "extracted", result.status
    assert_equal [ "Services" ], result.line_items.select { _1[:flow] == "expense" }.pluck(:label)
    assert_equal [ "Taxes", "Government transfers for capital" ],
      result.line_items.select { _1[:flow] == "revenue" }.pluck(:label)
    expense_total = result.facts.find { _1[:concept] == "total_expenses" }
    assert_equal 80, expense_total.fetch(:value)
    assert_equal "EXPENSE", expense_total.fetch(:raw_label)
    assert_equal BigDecimal("0.95"), expense_total.fetch(:extraction_confidence)
    assert_includes result.response.dig("details", "position_total_fallbacks"), {
      "concept" => "total_expenses", "type" => "unlabeled_section_total"
    }
    assert result.checks.find { _1[:id] == "line_sum:expense" && _1[:status] == "pass" }
  ensure
    source&.unlink
  end

  test "retries shaded total bands with thresholded table OCR" do
    source = Tempfile.new([ "municipal-statement", ".pdf" ])
    source.write("source")
    source.close
    sha = Digest::SHA256.file(source.path).hexdigest
    plain_position = <<~TEXT
      Statement of Financial Position 2025 2024
      Total Financial Assets
      Total Liabilities
      NET FINANCIAL ASSETS
      Total Non-Financial Assets
      ACCUMULATED SURPLUS
      100 90
      60 50
      40 40
      160 140
      200 180
    TEXT
    plain_operations = <<~TEXT
      Statement of Operations 2025 Budget 2025 2024
      REVENUES
      Taxes
      Total Revenues
      EXPENSES
      Services
      Total Expenses
      Annual Surplus
      100 100 90
      80 80 70
      20 20 20
    TEXT
    ocr_position = <<~TEXT
      Statement of Financial Position
      2025
      2024
      Total Financial Assets 100 90
      Total Liabilities 60 50
      NET FINANCIAL ASSETS 40 40
      Total Non-Financial Assets 160 140
      ACCUMULATED SURPLUS 200 180
    TEXT
    ocr_operations = <<~TEXT
      Statement of Operations
      2025 Budget 2025 2024
      REVENUES
      Taxes 100 100 90
      Total Revenues 100 100 90
      EXPENSES
      Services 80 80 70
      Total Expenses 80 80 70
      Surplus (Deficit) of Revenues over Expenses 20 20 20
      Accumulated Surplus, Beginning of Year 180 180 160
    TEXT
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => plain_position, 2 => plain_operations },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: []
    )
    locator = TableOcrLocator.new(located, { 1 => ocr_position, 2 => ocr_operations })

    result = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: source.path, institution_canonical_id: "ca/sk/example",
      document_canonical_id: "ca/sk/example/documents/financial-statements/2025/general",
      asset_sha256: sha, fiscal_year_end: Date.new(2025, 12, 31), page_locator: locator
    ).run

    assert_equal "extracted", result.status
    assert_equal [ 1, 2 ], locator.calls
    assert_equal [ 1, 2 ], result.locator_result.ocr_pages
    assert_equal 100, result.facts.find { _1[:concept] == "total_financial_assets" }.fetch(:value)
  ensure
    source&.unlink
  end

  test "keeps original position text when table OCR is also incomplete" do
    plain_position = <<~TEXT
      Statement of Financial Position 2025 2024
      Total Financial Assets
      Total Liabilities
      NET FINANCIAL ASSETS
      Total Non-Financial Assets
      ACCUMULATED SURPLUS
    TEXT
    operations = <<~TEXT
      Statement of Operations 2025 Budget 2025 2024
      Total Revenues 100 100 90
      Total Expenses 80 80 70
      Annual Surplus 20 20 20
    TEXT
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => plain_position, 2 => operations },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: []
    )
    locator = TableOcrLocator.new(located, { 1 => "Statement of Financial Position 2025 2024\nCash 100 90" })
    pipeline = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/sk/example",
      document_canonical_id: "ca/sk/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31), page_locator: locator
    )

    enriched = pipeline.send(:enrich_with_table_ocr, located)

    assert_equal [ 1 ], locator.calls
    assert_equal plain_position, enriched.page_texts.fetch(1)
    assert_empty enriched.ocr_pages
  end

  test "keeps original operations text when table OCR is also incomplete" do
    position = <<~TEXT
      Statement of Financial Position 2025 2024
      Total Financial Assets 100 90
      Total Liabilities 60 50
      NET FINANCIAL ASSETS 40 40
      Total Non-Financial Assets 160 140
      ACCUMULATED SURPLUS 200 180
    TEXT
    operations = <<~TEXT
      Statement of Operations 2025 Budget 2025 2024
      REVENUES
      Total Revenues
      EXPENSES
      Total Expenses
      Annual Surplus
    TEXT
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => position, 2 => operations },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: []
    )
    locator = TableOcrLocator.new(located, {
      2 => "Statement of Operations 2025 Budget 2025 2024\nTotal Revenues 100 100 90"
    })
    pipeline = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/sk/example",
      document_canonical_id: "ca/sk/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31), page_locator: locator
    )

    enriched = pipeline.send(:enrich_with_table_ocr, located)

    assert_equal [ 2 ], locator.calls
    assert_equal operations, enriched.page_texts.fetch(2)
    assert_empty enriched.ocr_pages
  end

  test "retries malformed operations values with table OCR exactly once" do
    source = Tempfile.new([ "municipal-statement", ".pdf" ])
    source.write("source")
    source.close
    sha = Digest::SHA256.file(source.path).hexdigest
    position = <<~TEXT
      2025 2024
      Total Financial Assets 100 90
      Total Liabilities 60 50
      NET FINANCIAL ASSETS 40 40
      Total Non-Financial Assets 160 140
      ACCUMULATED SURPLUS 200 180
    TEXT
    malformed_operations = <<~TEXT
      2025 Budget 2025 2024
      REVENUES
      Taxes 100 100 90
      Total Revenues 999 999 90
      EXPENSES
      Services 80 80 70
      Total Expenses 80 80 70
      Annual Surplus 20 20 20
      Accumulated Surplus, Beginning of Year 180 180 160
    TEXT
    corrected_operations = malformed_operations.sub("999 999 90", "100 100 90")
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => position, 2 => malformed_operations },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: []
    )
    locator = TableOcrLocator.new(located, { 2 => corrected_operations })

    result = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: source.path, institution_canonical_id: "ca/ab/example",
      document_canonical_id: "ca/ab/example/documents/financial-statements/2025/general",
      asset_sha256: sha, fiscal_year_end: Date.new(2025, 12, 31), page_locator: locator
    ).run

    assert_equal "extracted", result.status
    assert_equal [ 2 ], locator.calls
    assert_equal [ 2 ], result.locator_result.ocr_pages
    assert result.checks.find { _1[:id] == "operations_surplus" && _1[:status] == "pass" }
  ensure
    source&.unlink
  end

  test "does not retry an operations page already sourced from OCR" do
    source = Tempfile.new([ "municipal-statement", ".pdf" ])
    source.write("source")
    source.close
    sha = Digest::SHA256.file(source.path).hexdigest
    position = <<~TEXT
      2025 2024
      Total Financial Assets 100 90
      Total Liabilities 60 50
      NET FINANCIAL ASSETS 40 40
      Total Non-Financial Assets 160 140
      ACCUMULATED SURPLUS 200 180
    TEXT
    operations = <<~TEXT
      2025 Budget 2025 2024
      REVENUES
      Taxes 100 100 90
      Total Revenues 999 999 90
      EXPENSES
      Services 80 80 70
      Total Expenses 80 80 70
      Annual Surplus 20 20 20
      Accumulated Surplus, Beginning of Year 180 180 160
    TEXT
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 2, page_texts: { 1 => position, 2 => operations },
      position_page: 1, operations_page: 2, candidate_pages: [ 1, 2 ], ocr_pages: [ 2 ]
    )
    locator = TableOcrLocator.new(located, {})
    pipeline = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: source.path, institution_canonical_id: "ca/ab/example",
      document_canonical_id: "ca/ab/example/documents/financial-statements/2025/general",
      asset_sha256: sha, fiscal_year_end: Date.new(2025, 12, 31), page_locator: locator
    )

    assert_raises(Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::Unsupported) do
      pipeline.run
    end
    assert_empty locator.calls
  ensure
    source&.unlink
  end

  test "does not OCR after a source hash failure" do
    source = Tempfile.new([ "municipal-statement", ".pdf" ])
    source.write("source")
    source.close
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1, page_texts: { 1 => "Statement of Operations" },
      position_page: 1, operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    locator = TableOcrLocator.new(located, {})
    pipeline = Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline.new(
      pdf_path: source.path, institution_canonical_id: "ca/ab/example",
      document_canonical_id: "ca/ab/example/documents/financial-statements/2025/general",
      asset_sha256: "0" * 64, fiscal_year_end: Date.new(2025, 12, 31), page_locator: locator
    )

    assert_raises(Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::Unsupported) do
      pipeline.run
    end
    assert_empty locator.calls
  ensure
    source&.unlink
  end
end
