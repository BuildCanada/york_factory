require "test_helper"

class Warehouse::FinancialStatementExtraction::ReviewerTest < ActiveSupport::TestCase
  setup do
    @release = Warehouse::InstitutionRelease.create!(
      version: "2026-09-01", effective_on: Date.new(2026, 9, 1), schema_version: "1.0",
      published_at: Time.utc(2026, 9, 1), geography_vintage: 2021, attribution: "Test"
    )
    source = Warehouse::InstitutionSource.create!(
      institution_release: @release, canonical_id: "ca/sources/reviewer-test",
      publisher_name: "Test", title_en: "Test", url: "https://example.test/source",
      retrieved_at: @release.published_at, languages: [ "en" ]
    )
    institution = Warehouse::Institution.create!(
      institution_release: @release, institution_source: source, canonical_id: "ca/sk/example",
      name_en: "Example", institution_type: "government", government_level: "municipal", status: "active"
    )
    document = Warehouse::InstitutionDocument.create!(
      institution_release: @release, institution:, institution_source: source,
      canonical_id: "ca/sk/example/documents/financial-statements/2025/general",
      document_type: "financial-statements", document_variant: "general"
    )
    @asset_root = Pathname(Dir.mktmpdir)
    sha = Digest::SHA256.hexdigest("source")
    relative = Pathname("sha256/#{sha.first(2)}/#{sha}.pdf")
    path = @asset_root.join(relative)
    path.dirname.mkpath
    path.write("source")
    asset = Warehouse::InstitutionDocumentAsset.create!(
      institution_release: @release, institution_document: document, content_sha256: sha,
      asset_role: "final", preferred: true, download_url: "https://example.test/statement.pdf",
      retrieved_at: @release.published_at, archive_path: relative.to_s,
      mime_type: "application/pdf", byte_size: path.size, rights_status: "metadata_only"
    )
    @extraction = Warehouse::FinancialStatementExtraction.create!(
      institution_release: @release, institution_canonical_id: institution.canonical_id,
      document_canonical_id: document.canonical_id, asset_sha256: asset.content_sha256,
      fiscal_year_end: Date.new(2025, 12, 31), extractor_version: "detailed-psas-v1",
      status: "extracted", check_results: [
        { id: "source_identity", status: "pass", detail: "source hash matches" }
      ], llm_response_snapshot: { "headline" => {
        "remeasurement_present" => false, "operations_adjustment_present" => false,
        "rollforward_adjustment_present" => false
      } }
    )
    create_fact("total_financial_assets", 100, "financial_position")
    create_fact("total_liabilities", 60, "financial_position")
    create_fact("net_financial_assets", 40, "financial_position")
    create_fact("total_non_financial_assets", 160, "financial_position")
    create_fact("accumulated_surplus", 200, "financial_position")
    create_fact("total_revenue", 80, "operations")
    create_fact("total_expenses", 70, "operations")
    create_fact("annual_surplus", 10, "operations")
    create_line_item("revenue", "Revenue item", 80)
    create_line_item("expense", "Expense item", 70)
  end

  teardown { FileUtils.remove_entry(@asset_root) }

  test "independently revalidates source evidence and approves a detailed extraction" do
    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: locator
    ).review!

    assert_equal "approved", result.status
    assert_equal "approved", @extraction.reload.status
    assert_equal "deterministic-source-reaudit-v1", @extraction.reviewed_by
  end

  test "retries a result parked for review after deterministic checks improve" do
    @extraction.update!(status: "needs_review")

    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: locator
    ).review!

    assert_equal "approved", result.status
    assert_equal "approved", @extraction.reload.status
  end

  test "does not overwrite an approval committed while a slower review is auditing" do
    reviewer = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: locator
    )
    result = Warehouse::FinancialStatementExtraction::Reviewer::Result.new(
      status: "needs_review",
      checks: [ { id: "late_audit", status: "fail", detail: "stale result" } ]
    )
    reviewer.stub(:audit, -> {
      Warehouse::FinancialStatementExtraction.where(id: @extraction.id).update_all(
        status: "approved", reviewed_by: "deterministic-source-reaudit-v1",
        reviewed_at: Time.current, review_notes: "concurrent approval"
      )
      result
    }) do
      assert_equal result, reviewer.review!
    end

    @extraction.reload
    assert_equal "approved", @extraction.status
    assert_equal "deterministic-source-reaudit-v1", @extraction.reviewed_by
    assert_equal "concurrent approval", @extraction.review_notes
    refute_equal result.checks.map(&:stringify_keys), @extraction.check_results
  end

  test "audits an already approved extraction without mutating its review provenance" do
    @extraction.update!(check_results: [
      { id: "legacy_source_identity", status: "pass", detail: "legacy source check passed" }
    ])
    @extraction.approve!(reviewer: "legacy-reviewer")

    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: locator
    ).audit

    assert_equal "approved", result.status
    assert_equal "legacy-reviewer", @extraction.reload.reviewed_by
  end

  test "promotes a passing legacy approval while preserving prior provenance on the row" do
    legacy_checks = [
      { id: "legacy_source_identity", status: "pass", detail: "legacy source check passed" }
    ]
    @extraction.update!(check_results: legacy_checks)
    @extraction.approve!(reviewer: "legacy-reviewer")
    previous_reviewed_at = @extraction.reviewed_at
    previous_digest = Digest::SHA256.hexdigest(JSON.generate(legacy_checks))

    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: locator
    ).reaudit!

    assert_equal "approved", result.status
    assert_equal "deterministic-source-reaudit-v1", @extraction.reload.reviewed_by
    assert_operator @extraction.reviewed_at, :>, previous_reviewed_at
    assert_includes @extraction.review_notes, "previous reviewer=legacy-reviewer"
    assert_includes @extraction.review_notes, previous_digest
    assert_equal result.checks.map(&:stringify_keys), @extraction.check_results
  end

  test "does not mutate a legacy approval when its re-audit does not pass" do
    @extraction.financial_statement_facts.update_all(scale: 1000)
    @extraction.financial_statement_line_items.update_all(scale: 1000)
    @extraction.approve!(reviewer: "legacy-reviewer")
    before = @extraction.attributes.deep_dup

    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: locator
    ).reaudit!

    assert_equal "needs_review", result.status
    assert_equal before, @extraction.reload.attributes
  end

  test "does not mutate a legacy approval when its re-audit raises" do
    @extraction.approve!(reviewer: "legacy-reviewer")
    before = @extraction.attributes.deep_dup
    broken_locator = Object.new
    broken_locator.define_singleton_method(:locate) { raise "broken source reader" }
    reviewer = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: broken_locator
    )

    assert_raises(RuntimeError) { reviewer.reaudit! }
    assert_equal before, @extraction.reload.attributes
  end

  test "promotes a visually verified legacy approval with visual provenance" do
    @extraction.approve!(reviewer: "legacy-reviewer")
    response = { "claims" => [ {
      "id" => "evidence:total_expenses", "found" => true,
      "transcribed_label" => "Total expenses", "transcribed_category" => "",
      "raw_text" => "70", "column_year" => "Actual 2025", "excerpt_page" => 1
    } ] }

    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: visually_failing_locator,
      visual_llm_client: ->(**) { response }
    ).reaudit!

    assert_equal "approved", result.status
    assert_equal "deterministic-plus-visual-reaudit-v1", @extraction.reload.reviewed_by
    assert_includes @extraction.review_notes, "blind visual source transcription also matched"
  end

  test "independently reviews prairie parser evidence using table OCR text" do
    @extraction.update!(llm_response_snapshot: @extraction.llm_response_snapshot.merge(
      "parser" => Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::PARSER_VERSION
    ))
    base = locator.locate
    table_locator = Struct.new(:result, :calls) do
      def locate = result
      def ocr_table_page(page)
        calls << page
        result.page_texts.fetch(page)
      end
    end.new(base, [])

    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: table_locator
    ).review!

    assert_equal "approved", result.status
    assert_equal [ 1 ], table_locator.calls
  end

  test "retains independent table OCR review support for prairie parser v2" do
    @extraction.update!(llm_response_snapshot: @extraction.llm_response_snapshot.merge(
      "parser" => "prairie-municipal-form-v2"
    ))
    base = locator.locate
    table_locator = Struct.new(:result, :calls) do
      def locate = result
      def ocr_table_page(page)
        calls << page
        result.page_texts.fetch(page)
      end
    end.new(base, [])
    reviewer = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: table_locator
    )

    assert_equal 8, reviewer.send(:review_ocr_page_limit)
    reviewer.send(:enrich_parser_table_ocr, base, table_locator)
    assert_equal [ 1 ], table_locator.calls
  end

  test "independently reviews cited Quebec form pages using saved OCR provenance" do
    @extraction.update!(llm_response_snapshot: @extraction.llm_response_snapshot.merge(
      "parser" => Warehouse::FinancialStatementExtraction::QuebecFormPipeline::PARSER_VERSION,
      "details" => { "ocr_pages" => [ 1 ] }
    ))
    base = locator.locate
    table_locator = Struct.new(:result, :calls) do
      def locate = result
      def ocr_table_page(page)
        calls << page
        result.page_texts.fetch(page)
      end
    end.new(base, [])

    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: table_locator
    ).review!

    assert_equal "approved", result.status
    assert_equal [ 1 ], table_locator.calls
  end

  test "table OCRs unique valid generic evidence pages with a hard cap" do
    last_item = nil
    13.times do |index|
      last_item = create_line_item("expense", "Extra #{index}", index + 1)
      last_item.update!(source_page: index + 2)
    end
    last_item.update!(source_page: 99)
    pages = (1..14).index_with { "source" }
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 14, page_texts: pages, position_page: 1,
      operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    table_locator = Struct.new(:result, :calls) do
      def ocr_table_page(page)
        calls << page
        result.page_texts.fetch(page)
      end
    end.new(located, [])
    reviewer = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: table_locator
    )

    reviewer.send(:enrich_parser_table_ocr, located, table_locator)

    assert_equal (1..12).to_a, table_locator.calls
    refute_includes table_locator.calls, 99
  end

  test "blind visual transcription can clear the only deterministic evidence failure" do
    visual_calls = []
    response = { "claims" => [ {
      "id" => "evidence:total_expenses", "found" => true,
      "transcribed_label" => "Total expenses", "transcribed_category" => "",
      "raw_text" => "70", "column_year" => "Actual 2025", "excerpt_page" => 1
    } ] }
    result = Warehouse::FinancialStatementExtraction::Reviewer.new(
      extraction: @extraction, asset_root: @asset_root, page_locator: visually_failing_locator,
      visual_llm_client: ->(prompt:, pdf_path:) do
        visual_calls << [ prompt, pdf_path ]
        response
      end
    ).review!

    assert_equal "approved", result.status
    assert_equal "deterministic-plus-visual-reaudit-v1", @extraction.reload.reviewed_by
    assert_equal 1, visual_calls.length
    refute_includes visual_calls.first.first, "raw_text: 70"
    assert_equal "pass", result.checks.find { _1[:id] == "visual_evidence:evidence:total_expenses" }[:status]
  end

  test "visual verifier refuses mismatched values" do
    checks = [ { id: "evidence:total_expenses", status: "fail", detail: "OCR miss" } ]
    response = { "claims" => [ {
      "id" => "evidence:total_expenses", "found" => true,
      "transcribed_label" => "Total expenses", "transcribed_category" => "",
      "raw_text" => "71", "column_year" => "Actual 2025", "excerpt_page" => 1
    } ] }
    result = Warehouse::FinancialStatementExtraction::VisualEvidenceReviewer.new(
      extraction: @extraction, page_locator: visually_failing_locator,
      llm_client: ->(**) { response }
    ).apply(checks)

    assert_equal "fail", result.find { _1[:id] == "evidence:total_expenses" }[:status]
    visual = result.find { _1[:id] == "visual_evidence:evidence:total_expenses" }
    assert_equal "fail", visual[:status]
    assert_includes visual[:detail], "value mismatch"
  end

  test "visual verifier is gated off by any non-evidence failure" do
    called = false
    checks = [
      { id: "evidence:total_expenses", status: "fail", detail: "OCR miss" },
      { id: "line_sum:expense", status: "fail", detail: "incomplete" }
    ]
    result = Warehouse::FinancialStatementExtraction::VisualEvidenceReviewer.new(
      extraction: @extraction, page_locator: visually_failing_locator,
      llm_client: ->(**) { called = true }
    ).apply(checks)

    refute called
    assert_equal checks, result
  end

  test "visual verifier uses sorted physical pages and rejects incomplete responses" do
    @extraction.financial_statement_facts.find_by!(concept: "total_expenses").update!(source_page: 2)
    expense = @extraction.financial_statement_line_items.find_by!(flow: "expense")
    checks = [
      { id: "evidence:total_expenses", status: "fail", detail: "OCR miss" },
      { id: "line_evidence:expense-items-expense-item", status: "fail", detail: "OCR miss" }
    ]
    pages_seen = []
    excerpt_locator = Struct.new(:pages_seen) do
      def with_excerpt(pages)
        pages_seen << pages
        yield Pathname("visual.pdf")
      end
    end.new(pages_seen)
    result = Warehouse::FinancialStatementExtraction::VisualEvidenceReviewer.new(
      extraction: @extraction, page_locator: excerpt_locator,
      llm_client: ->(**) do
        { "claims" => [ {
          "id" => "evidence:total_expenses", "found" => true,
          "transcribed_label" => "Total expenses", "transcribed_category" => "",
          "raw_text" => "70", "column_year" => "2025", "excerpt_page" => 2
        } ] }
      end
    ).apply(checks)

    assert_equal [ [ 1, 2 ] ], pages_seen
    assert_equal "fail", result.find { _1[:id] == "visual_evidence:verifier" }[:status]
    assert_equal 1, expense.source_page
  end

  private

  def locator
    text = (@extraction.financial_statement_facts.map { "#{_1.raw_label} #{_1.raw_text}" } +
      @extraction.financial_statement_line_items.map { "#{_1.label} #{_1.raw_text}" }).join(" ")
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1, page_texts: { 1 => text }, position_page: 1,
      operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    Struct.new(:result) do
      def locate = result
      def ocr_table_page(page) = result.page_texts.fetch(page)
    end.new(located)
  end

  def visually_failing_locator
    text = (@extraction.financial_statement_facts.map { "#{_1.raw_label} #{_1.raw_text}" } +
      @extraction.financial_statement_line_items.map { "#{_1.label} #{_1.raw_text}" }).join(" ")
      .sub("Total expenses 70", "Expenses 70")
    located = Warehouse::FinancialStatementExtraction::PageLocator::Result.new(
      page_count: 1, page_texts: { 1 => text }, position_page: 1,
      operations_page: 1, candidate_pages: [ 1 ], ocr_pages: []
    )
    Struct.new(:result) do
      def locate = result
      def ocr_table_page(page) = result.page_texts.fetch(page)
      def with_excerpt(_pages) = yield(Pathname("visual.pdf"))
    end.new(located)
  end

  def create_fact(concept, value, statement)
    @extraction.financial_statement_facts.create!(
      concept:, value:, raw_text: value.to_s, raw_label: concept.humanize,
      scale: 1, statement:, source_page: 1, column_year: "2025", extraction_confidence: 0.99
    )
  end

  def create_line_item(flow, label, value)
    position = @extraction.financial_statement_line_items.where(flow:).maximum(:position).to_i
    position += 1 if @extraction.financial_statement_line_items.where(flow:).exists?
    @extraction.financial_statement_line_items.create!(
      flow:, category: "Items", label:, value:, raw_text: value.to_s,
      scale: 1, source_page: 1, column_year: "2025", position:, extraction_confidence: 0.99
    )
  end
end
