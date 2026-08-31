class Warehouse::FinancialStatementExtraction::StoredHeadlinePipeline
  def initialize(extraction:, pdf_path:, page_locator: nil, allow_needs_review: false)
    @extraction = extraction
    @pdf_path = Pathname(pdf_path)
    @page_locator = page_locator || Warehouse::FinancialStatementExtraction::PageLocator.new(@pdf_path)
    @allow_needs_review = allow_needs_review
  end

  def run
    allowed_statuses = %w[extracted approved]
    allowed_statuses << "needs_review" if @allow_needs_review
    unless @extraction.status.in?(allowed_statuses)
      raise ArgumentError, "stored headline extraction must be extracted or approved"
    end
    raise ArgumentError, "stored extraction is not a headline extraction" unless @extraction.extractor_version == Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
    actual_sha = Digest::SHA256.file(@pdf_path).hexdigest
    raise ArgumentError, "stored headline asset SHA mismatch" unless actual_sha == @extraction.asset_sha256

    locator_result = @page_locator.locate
    facts = @extraction.financial_statement_facts.map do |fact|
      fact.attributes.symbolize_keys.slice(
        :concept, :value, :raw_text, :raw_label, :scale, :statement,
        :source_page, :column_year, :extraction_confidence
      )
    end
    Warehouse::FinancialStatementExtraction::Pipeline::Result.new(
      status: @extraction.status, facts:,
      checks: Array(@extraction.check_results).map(&:deep_symbolize_keys),
      prompt: @extraction.llm_prompt_snapshot&.fetch("prompt", nil),
      response: Hash(@extraction.llm_response_snapshot), locator_result:,
      language: @extraction.language, statement_basis: @extraction.statement_basis
    )
  end
end
