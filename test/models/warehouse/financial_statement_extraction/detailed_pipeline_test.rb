require "test_helper"

class Warehouse::FinancialStatementExtraction::DetailedPipelineTest < ActiveSupport::TestCase
  test "normalizes detailed line items and accepts reconciled leaf sums" do
    facts = [
      fact("total_financial_assets", "100,000", 100_000_000, "financial_position"),
      fact("total_liabilities", "60,000", 60_000_000, "financial_position"),
      fact("net_financial_assets", "40,000", 40_000_000, "financial_position"),
      fact("total_non_financial_assets", "160,000", 160_000_000, "financial_position"),
      fact("accumulated_surplus", "200,000", 200_000_000, "financial_position"),
      fact("total_revenue", "80,000", 80_000_000, "operations"),
      fact("total_expenses", "70,000", 70_000_000, "operations"),
      fact("annual_surplus", "10,000", 10_000_000, "operations")
    ]
    page_text = facts.map { |row| "#{row[:raw_label]} #{row[:raw_text]}" }.join(" ") +
      " Revenue expense schedule Property taxes 80,000 Operations 70,000"
    locator_result = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1, page_texts: { 1 => page_text }, position_page: 1,
      operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    headline = Warehouse::FinancialStatementExtraction::Pipeline::Result.new(
      status: "extracted", facts:, checks: [ { id: "source_identity", status: "pass", detail: "ok" } ],
      prompt: "headline", response: {
        "remeasurement_present" => false, "operations_adjustment_present" => false,
        "rollforward_adjustment_present" => false
      }, locator_result:, language: "en", statement_basis: "consolidated"
    )
    headline_pipeline = Struct.new(:result) { def run = result }.new(headline)
    page_locator = Struct.new(:result, :excerpt_calls) do
      def with_excerpt(pages)
        excerpt_calls << pages
        yield Pathname("detail-#{pages.join('-')}.pdf")
      end
    end.new(locator_result, [])
    attachments = []
    responses = {
      "revenue" => { "flow" => "revenue", "category" => "Taxes", "label" => "Property taxes",
        "raw_text" => "80,000", "scale" => 1_000, "excerpt_page" => 1,
        "column_year" => "2025", "confidence" => 0.99 },
      "expense" => { "flow" => "expense", "category" => "Services", "label" => "Operations",
        "raw_text" => "70,000", "scale" => 1_000, "excerpt_page" => 1,
        "column_year" => "2025", "confidence" => 0.99 },
      "empty" => { "flow" => "expense", "category" => "Services", "label" => "Unused program",
        "raw_text" => '"', "scale" => 1_000, "excerpt_page" => 1,
        "column_year" => "2025", "confidence" => 0.99 }
    }
    active_flow_calls = 0
    maximum_flow_calls = 0
    flow_call_mutex = Mutex.new
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/on/example",
      institution_name: "Example", document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31),
      headline_pipeline:, page_locator:, llm_client: ->(prompt:, pdf_path:) do
        flow_call_mutex.synchronize do
          active_flow_calls += 1
          maximum_flow_calls = [ maximum_flow_calls, active_flow_calls ].max
        end
        attachments << pdf_path
        flow = prompt.include?("REQUESTED FLOW: revenue") ? "revenue" : "expense"
        items = [ responses.fetch(flow) ]
        items << responses.fetch("empty") if flow == "expense"
        { "fiscal_year" => 2025, "line_items" => items }
      ensure
        flow_call_mutex.synchronize { active_flow_calls -= 1 }
      end
    )

    result = pipeline.run

    assert_equal "extracted", result.status
    assert_equal [ "revenue", "expense" ], result.line_items.map { |item| item.fetch(:flow) }
    assert_equal BigDecimal("80000000"), result.line_items.first.fetch(:value)
    assert_equal [ [ 1 ], [ 1 ] ], page_locator.excerpt_calls
    assert_equal [ "detail-1.pdf", "detail-1.pdf" ], attachments
    assert_equal 1, maximum_flow_calls

    headline_pipeline.result = headline.with(status: "needs_review")
    assert_equal "needs_review", pipeline.run.status
  end

  test "adds flow-specific schedule pages to the primary operations page" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 4,
      page_texts: {
        1 => "Statement of Operations 2025 Revenue 80,000 Expenses 70,000",
        2 => "Schedule A - Revenue 2025 Taxes 50,000 Transfers 30,000",
        3 => "Schedule B - Expenses 2025 Wages 40,000 Supplies 30,000",
        4 => "Notes 2025 Revenue recognition 80,000"
      },
      position_page: 1, operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/on/example",
      institution_name: "Example",
      document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31)
    )

    assert_equal [ 1, 2 ], pipeline.send(:select_detail_pages, locator, "revenue")
    assert_equal [ 1, 3 ], pipeline.send(:select_detail_pages, locator, "expense")
  end

  test "caps detail extraction at the operations page plus three schedules" do
    page_texts = { 1 => "Statement of Operations 2025 Revenue 80,000 Expenses 70,000" }
    5.times do |index|
      page_texts[index + 2] = "Schedule #{index + 1} - Expenses 2025 Wages #{40_000 + index},000 Supplies 30,000"
    end
    locator = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 6, page_texts:, position_page: 1, operations_page: 1,
      candidate_pages: [ 1 ], ocr_pages: []
    )
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/on/example",
      institution_name: "Example",
      document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31)
    )

    assert_equal 4, pipeline.send(:select_detail_pages, locator, "expense").length
  end

  test "sorts detail pages to match the attached excerpt order" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 4,
      page_texts: {
        1 => "Schedule A - Expenses 2025 Wages 40,000 Supplies 30,000",
        3 => "Statement of Operations 2025 Revenue 80,000 Expenses 70,000"
      },
      position_page: 3, operations_page: 3, candidate_pages: [ 3 ], ocr_pages: []
    )
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/on/example",
      institution_name: "Example",
      document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31)
    )

    assert_equal [ 1, 3 ], pipeline.send(:select_detail_pages, locator, "expense")
  end

  test "uses only the primary operations page when it already prints detailed flow rows" do
    locator = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 3,
      page_texts: {
        1 => <<~TEXT,
          Statement of Operations
          Revenue
          Property taxes 1,000 900
          Government transfers 2,000 1,800
          Expenses
          General government 1,200 1,100
          Transportation 1,300 1,200
          Total expenses 2,500 2,300
        TEXT
        2 => "Schedule A - Revenue 2025 Taxes 1,000 Transfers 2,000",
        3 => "Schedule B - Expenses 2025 Wages 1,200 Supplies 1,300"
      },
      position_page: 1, operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/on/example",
      institution_name: "Example",
      document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31)
    )

    assert_equal [ 1 ], pipeline.send(:select_detail_pages, locator, "revenue")
    assert_equal [ 1 ], pipeline.send(:select_detail_pages, locator, "expense")
    prompt = pipeline.send(:build_prompt, [ 1 ], locator.page_texts, "expense")
    assert_includes prompt, "strictly between the Expenses heading and Total Expenses or Total Expenditures"
    assert_includes prompt, "row after those totals"
  end

  test "rejects responses that exceed the application safety limit" do
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      pdf_path: "unused.pdf", institution_canonical_id: "ca/on/example",
      institution_name: "Example",
      document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31)
    )
    item = {
      "flow" => "revenue", "category" => "Taxes", "label" => "Property taxes",
      "raw_text" => "1", "scale" => 1, "excerpt_page" => 1,
      "column_year" => "2025", "confidence" => 0.99
    }
    response = { "fiscal_year" => 2025, "line_items" => Array.new(101) { |index| item.merge("label" => "Row #{index}") } }

    error = assert_raises(Warehouse::FinancialStatementExtraction::DetailedPipeline::ResponseError) do
      pipeline.send(:validate_response!, response, [ 1 ], "revenue")
    end
    assert_equal "too many line items", error.message
  end

  test "validates flow concurrency and requires isolated concurrent clients" do
    attributes = pipeline_attributes

    error = assert_raises(ArgumentError) do
      Warehouse::FinancialStatementExtraction::DetailedPipeline.new(**attributes, flow_concurrency: 3)
    end
    assert_equal "flow_concurrency must be 1 or 2", error.message

    error = assert_raises(ArgumentError) do
      Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
        **attributes, flow_concurrency: 2, llm_client: ->(**) { nil }
      )
    end
    assert_equal "concurrent flow extraction requires llm_client_factory", error.message

    shared_client = ->(**) { nil }
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      **attributes, flow_concurrency: 2, llm_client_factory: -> { shared_client }
    )
    error = assert_raises(Warehouse::FinancialStatementExtraction::DetailedPipeline::ResponseError) do
      pipeline.run
    end
    assert_equal "llm_client_factory must return a distinct callable per flow", error.message
  end

  test "concurrent flow calls overlap but return deterministic results and clean excerpts" do
    gates = { "revenue" => Queue.new, "expense" => Queue.new }
    started = Queue.new
    completed = Queue.new
    paths = Queue.new
    events = Queue.new
    client_factory = lambda do
      lambda do |prompt:, pdf_path:|
        flow = prompt.include?("REQUESTED FLOW: revenue") ? "revenue" : "expense"
        paths << pdf_path
        started << flow
        gates.fetch(flow).pop
        completed << flow
        detail_response(flow)
      end
    end
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      **pipeline_attributes, flow_concurrency: 2, llm_client_factory: client_factory,
      flow_reporter: ->(event) { events << event }
    )

    runner = Thread.new { pipeline.run }
    observed = Timeout.timeout(2) { 2.times.map { started.pop }.sort }
    assert_equal %w[expense revenue], observed
    gates.fetch("expense") << true
    assert_equal "expense", Timeout.timeout(2) { completed.pop }
    gates.fetch("revenue") << true
    result = Timeout.timeout(2) { runner.value }

    assert_equal %w[revenue expense], result.line_items.map { _1.fetch(:flow) }
    assert_equal %w[revenue expense], result.response.fetch("details").keys
    materialized_paths = 2.times.map { paths.pop }
    assert materialized_paths.all? { |path| !File.exist?(path) }
    reported = 2.times.map { events.pop }
    assert_equal %w[expense revenue], reported.map { _1.fetch(:flow) }.sort
    assert reported.all? { _1.fetch(:financial_statement_detail_flow) == "success" }
  end

  test "concurrent flow failure joins its sibling and removes every excerpt" do
    sibling_finished = false
    paths = Queue.new
    events = Queue.new
    client_factory = lambda do
      lambda do |prompt:, pdf_path:|
        flow = prompt.include?("REQUESTED FLOW: revenue") ? "revenue" : "expense"
        paths << pdf_path
        raise "revenue failed" if flow == "revenue"

        sleep 0.05
        sibling_finished = true
        detail_response(flow)
      end
    end
    pipeline = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(
      **pipeline_attributes, flow_concurrency: 2, llm_client_factory: client_factory,
      flow_reporter: ->(event) { events << event }
    )

    error = assert_raises(RuntimeError) { pipeline.run }

    assert_equal "revenue failed", error.message
    assert sibling_finished
    materialized_paths = 2.times.map { paths.pop }
    assert materialized_paths.all? { |path| !File.exist?(path) }
    reported = 2.times.map { events.pop }
    assert_equal [ "failure", "success" ], reported.map { _1.fetch(:financial_statement_detail_flow) }.sort
  end

  private

  def pipeline_attributes
    facts = [
      fact("total_financial_assets", "100,000", 100_000_000, "financial_position"),
      fact("total_liabilities", "60,000", 60_000_000, "financial_position"),
      fact("net_financial_assets", "40,000", 40_000_000, "financial_position"),
      fact("total_non_financial_assets", "160,000", 160_000_000, "financial_position"),
      fact("accumulated_surplus", "200,000", 200_000_000, "financial_position"),
      fact("total_revenue", "80,000", 80_000_000, "operations"),
      fact("total_expenses", "70,000", 70_000_000, "operations"),
      fact("annual_surplus", "10,000", 10_000_000, "operations")
    ]
    locator_result = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1,
      page_texts: { 1 => "Revenue Property taxes 80,000 80,000 Expenses Operations 70,000 70,000" },
      position_page: 1, operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    headline = Warehouse::FinancialStatementExtraction::Pipeline::Result.new(
      status: "extracted", facts:,
      checks: [ { id: "source_identity", status: "pass", detail: "ok" } ],
      prompt: "headline", response: {
        "remeasurement_present" => false, "operations_adjustment_present" => false,
        "rollforward_adjustment_present" => false
      }, locator_result:, language: "en", statement_basis: "consolidated"
    )
    headline_pipeline = Struct.new(:result) { def run = result }.new(headline)
    page_locator = Class.new do
      def with_excerpt(_pages)
        Dir.mktmpdir("detailed-pipeline-test") do |directory|
          path = Pathname(directory).join("excerpt.pdf")
          path.write("%PDF-test")
          yield path
        end
      end
    end.new
    {
      pdf_path: "unused.pdf", institution_canonical_id: "ca/on/example",
      institution_name: "Example",
      document_canonical_id: "ca/on/example/documents/financial-statements/2025/general",
      asset_sha256: "a" * 64, fiscal_year_end: Date.new(2025, 12, 31),
      headline_pipeline:, page_locator:
    }
  end

  def detail_response(flow)
    amount = flow == "revenue" ? "80,000" : "70,000"
    {
      "fiscal_year" => 2025,
      "line_items" => [ {
        "flow" => flow, "category" => flow == "revenue" ? "Taxes" : "Services",
        "label" => flow == "revenue" ? "Property taxes" : "Operations",
        "raw_text" => amount, "scale" => 1_000, "excerpt_page" => 1,
        "column_year" => "2025", "confidence" => 0.99
      } ]
    }
  end

  def fact(concept, raw_text, value, statement)
    {
      concept:, raw_label: concept.humanize, raw_text:, value: BigDecimal(value.to_s),
      scale: 1_000, statement:, source_page: 1, column_year: "2025",
      extraction_confidence: BigDecimal("0.99")
    }
  end
end
