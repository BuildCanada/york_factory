require "digest"

class Warehouse::FinancialStatementExtraction::Reviewer
  REVIEWER = "deterministic-source-reaudit-v1"
  VISUAL_REVIEWER = "deterministic-plus-visual-reaudit-v1"
  DETERMINISTIC_REVIEWERS = [ REVIEWER, VISUAL_REVIEWER ].freeze
  GENERIC_TABLE_OCR_PAGE_LIMIT = 12
  DEFAULT_ASSET_ROOT = Warehouse::FinancialStatementExtraction::CandidateSet::DEFAULT_ASSET_ROOT
  Result = Data.define(:status, :checks)

  def initialize(extraction:, asset_root: ENV.fetch("PUBLIC_INSTITUTION_ASSET_ROOT", DEFAULT_ASSET_ROOT.to_s),
    page_locator: nil, visual_model: Warehouse::FinancialStatementExtraction::VisualEvidenceReviewer::DEFAULT_MODEL,
    visual_llm_client: nil)
    @extraction = extraction
    @asset_root = Pathname(asset_root).expand_path
    @page_locator = page_locator
    @visual_model = visual_model
    @visual_llm_client = visual_llm_client
  end

  def review!
    validate_reviewable!
    result = audit
    @extraction.with_lock do
      return result if @extraction.reviewed_at?

      validate_reviewable!
      @extraction.update!(check_results: result.checks)
      if result.status == "approved"
        @extraction.approve!(
          reviewer: deterministic_reviewer(result.checks),
          notes: deterministic_review_notes(result.checks)
        )
      else
        @extraction.update!(status: "needs_review", error_message: "independent deterministic re-audit failed")
      end
    end
    result
  end

  def reaudit!
    validate_reauditable!
    result = audit
    return result unless result.status == "approved"

    previous_reviewer = @extraction.reviewed_by
    previous_reviewed_at = @extraction.reviewed_at
    previous_checks = @extraction.check_results.deep_dup
    previous_digest = Digest::SHA256.hexdigest(JSON.generate(previous_checks))
    provenance = "previous reviewer=#{previous_reviewer} at #{previous_reviewed_at.iso8601}; " \
      "#{previous_checks.length} checks sha256=#{previous_digest}"
    @extraction.transaction do
      @extraction.update!(
        check_results: result.checks,
        reviewed_by: deterministic_reviewer(result.checks),
        reviewed_at: Time.current,
        review_notes: "#{deterministic_review_notes(result.checks)}; legacy provenance: #{provenance}"
      )
    end
    result
  end

  def audit
    validate_detailed!
    document, asset, pdf_path = source
    source_check = verify_source(document, asset, pdf_path)
    if source_check.fetch(:status) == "fail"
      return Result.new(status: "needs_review", checks: [ source_check ])
    end
    locator = @page_locator || Warehouse::FinancialStatementExtraction::PageLocator.new(
      pdf_path, max_ocr_pages: review_ocr_page_limit
    )
    located = align_parser_pages(locator.locate)
    located = enrich_parser_table_ocr(located, locator)
    audit_validator = validator(located)
    validation_checks = audit_validator.validate
    scale_check = source_scale_check(located)
    checks = [ source_check, scale_check, *validation_checks ]
    unless audit_validator.acceptable?(validation_checks)
      checks = Warehouse::FinancialStatementExtraction::VisualEvidenceReviewer.new(
        extraction: @extraction, page_locator: locator, model: @visual_model,
        llm_client: @visual_llm_client
      ).apply(checks)
    end
    status = if scale_check.fetch(:status) == "pass" && audit_validator.acceptable?(checks)
      "approved"
    else
      "needs_review"
    end

    Result.new(status:, checks:)
  end

  private

  def validate_reviewable!
    validate_detailed!
    unless @extraction.status.in?(%w[extracted needs_review])
      raise ArgumentError, "extraction must be extracted or awaiting review"
    end
    raise ArgumentError, "reviewed extraction is immutable" if @extraction.reviewed_at?
  end

  def validate_reauditable!
    validate_detailed!
    raise ArgumentError, "only approved extractions can be re-audited" unless @extraction.status == "approved"
    unless @extraction.reviewed_at? && @extraction.reviewed_by?
      raise ArgumentError, "approved extraction must have existing review provenance"
    end
    if @extraction.reviewed_by.in?(DETERMINISTIC_REVIEWERS)
      raise ArgumentError, "extraction already has current deterministic review provenance"
    end
  end

  def validate_detailed!
    unless @extraction.extractor_version == Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
      raise ArgumentError, "only detailed extractions can be reviewed"
    end
  end

  def deterministic_reviewer(checks)
    visual = checks.any? { _1[:id].start_with?("visual_evidence:") && _1[:status] == "pass" }
    visual ? VISUAL_REVIEWER : REVIEWER
  end

  def deterministic_review_notes(checks)
    visual = deterministic_reviewer(checks) == VISUAL_REVIEWER
    "Source hash, units, page evidence, raw parsing, accounting identities, and line sums " \
      "independently revalidated#{'; blind visual source transcription also matched' if visual}"
  end

  def source
    document = @extraction.institution_release.institution_documents.find_by!(
      canonical_id: @extraction.document_canonical_id
    )
    asset = document.institution_document_assets.find_by!(content_sha256: @extraction.asset_sha256)
    pdf_path = @asset_root.join(asset.archive_path).expand_path
    unless pdf_path.to_s.start_with?("#{@asset_root}/")
      raise ArgumentError, "asset path escapes root"
    end
    [ document, asset, pdf_path ]
  end

  def verify_source(document, asset, pdf_path)
    return check("source_identity", "fail", "archived PDF is missing") unless pdf_path.file?

    actual = Digest::SHA256.file(pdf_path).hexdigest
    status = actual == asset.content_sha256 ? "pass" : "fail"
    check(
      "source_identity", status,
      "document=#{document.canonical_id}; expected=#{asset.content_sha256}; actual=#{actual}"
    )
  end

  def validator(located)
    Warehouse::FinancialStatementExtraction::Validator.new(
      facts: @extraction.financial_statement_facts.map { fact_attributes(_1) },
      line_items: @extraction.financial_statement_line_items.map { line_item_attributes(_1) },
      fiscal_year: @extraction.fiscal_year_end.year,
      page_texts: located.page_texts,
      flags: audited_flags(located)
    )
  end

  def headline_response
    Hash(@extraction.llm_response_snapshot).fetch("headline", {})
  end

  def review_ocr_page_limit
    case Hash(@extraction.llm_response_snapshot)["parser"]
    when Warehouse::FinancialStatementExtraction::QuebecFormPipeline::PARSER_VERSION then 0
    when *Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::REVIEWABLE_PARSER_VERSIONS then 8
    else 20
    end
  end

  def align_parser_pages(located)
    parser = Hash(@extraction.llm_response_snapshot)["parser"]
    return located unless parser == Warehouse::FinancialStatementExtraction::QuebecFormPipeline::PARSER_VERSION

    operations_page = @extraction.financial_statement_facts.find_by(concept: "total_revenue")&.source_page
    position_page = @extraction.financial_statement_facts.find_by(concept: "total_financial_assets")&.source_page
    return located unless operations_page && position_page

    candidates = [ operations_page - 1, operations_page, position_page, position_page + 1 ]
      .select { _1.between?(1, located.page_count) }.uniq.sort
    located.with(operations_page:, position_page:, candidate_pages: candidates)
  end

  def enrich_parser_table_ocr(located, locator)
    parser = Hash(@extraction.llm_response_snapshot)["parser"]
    pages = if parser.in?(
      Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline::REVIEWABLE_PARSER_VERSIONS
    )
      [ located.position_page, located.operations_page ].uniq
    elsif parser == Warehouse::FinancialStatementExtraction::QuebecFormPipeline::PARSER_VERSION
      Array(Hash(@extraction.llm_response_snapshot).dig("details", "ocr_pages")).map { Integer(_1) }
    else
      (@extraction.financial_statement_facts.pluck(:source_page) +
        @extraction.financial_statement_line_items.pluck(:source_page))
        .uniq.sort.select { _1.between?(1, located.page_count) && located.page_texts.key?(_1) }
        .first(GENERIC_TABLE_OCR_PAGE_LIMIT)
    end
    return located if pages.empty?

    replacements = pages.to_h do |page|
      [ page, [ located.page_texts.fetch(page), locator.ocr_table_page(page) ].join("\n") ]
    end
    located.with(
      page_texts: located.page_texts.merge(replacements),
      ocr_pages: (located.ocr_pages + pages).uniq.sort
    )
  end

  def source_scale_check(located)
    expected = Warehouse::FinancialStatementExtraction::ScaleDetector.detect(
      located.page_texts.values_at(located.operations_page, located.position_page)
    )
    stored = (@extraction.financial_statement_facts.pluck(:scale) +
      @extraction.financial_statement_line_items.pluck(:scale)).uniq
    status = stored == [ expected ] ? "pass" : "fail"
    check("source_scale", status, "source=#{expected}; stored=#{stored.sort.join(',')}")
  end

  def audited_flags(located)
    facts = @extraction.financial_statement_facts.index_by(&:concept)
    position_text = located.page_texts.fetch(located.position_page)
    operations_text = located.page_texts.fetch(located.operations_page)
    cited_text = @extraction.financial_statement_facts.pluck(:source_page).uniq
      .map { located.page_texts[_1].to_s }.join("\n")
    operations_discrepancy = if facts.values_at("total_revenue", "total_expenses", "annual_surplus").all?
      facts["total_revenue"].value - facts["total_expenses"].value - facts["annual_surplus"].value
    end
    rollforward_discrepancy = if facts.values_at("opening_accumulated_surplus", "annual_surplus", "accumulated_surplus").all?
      facts["opening_accumulated_surplus"].value + facts["annual_surplus"].value - facts["accumulated_surplus"].value
    end
    {
      remeasurement_present: position_text.match?(/remeasurement|remesurement|réévaluation|reevaluation/i),
      operations_adjustment_present: operations_discrepancy&.nonzero? &&
        operations_text.match?(/capital(?:-related)? (?:contributions|transfers)|contributed|donated tangible capital|transfers?(?: related to| relating to| for) capital|gain|loss|restructur/i),
      rollforward_adjustment_present: rollforward_discrepancy&.nonzero? &&
        cited_text.match?(/remeasurement|remesurement|restat|retrait|adjust|redress|other comprehensive.{0,30}(?:income|loss)|réévaluation|reevaluation/i),
      single_component_concepts:
        Warehouse::FinancialStatementExtraction::Pipeline.single_component_concepts(headline_response)
    }
  end

  def fact_attributes(fact)
    fact.attributes.symbolize_keys.slice(
      :concept, :value, :raw_text, :raw_label, :scale, :statement,
      :source_page, :column_year, :extraction_confidence
    )
  end

  def line_item_attributes(item)
    item.attributes.symbolize_keys.slice(
      :flow, :category, :label, :value, :raw_text, :scale,
      :source_page, :column_year, :position, :extraction_confidence
    )
  end

  def check(id, status, detail) = { id:, status:, detail: }
end
