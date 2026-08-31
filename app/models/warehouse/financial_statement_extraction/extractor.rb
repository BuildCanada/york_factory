class Warehouse::FinancialStatementExtraction::Extractor < ActiveRecord::AssociatedObject
  performs :extract, queue_as: :default

  def extract(pdf_path:, institution_name:, population: nil)
    raise ArgumentError, "reviewed extractions are immutable; create a new extractor version" if financial_statement_extraction.reviewed_at.present?

    financial_statement_extraction.update!(status: "extracting", error_message: nil)
    result = headline_pipeline(
      pdf_path:,
      institution_canonical_id: financial_statement_extraction.institution_canonical_id,
      institution_name:,
      document_canonical_id: financial_statement_extraction.document_canonical_id,
      asset_sha256: financial_statement_extraction.asset_sha256,
      fiscal_year_end: financial_statement_extraction.fiscal_year_end,
      population:,
      model: financial_statement_extraction.llm_model.presence || Warehouse::FinancialStatementExtraction::Pipeline::DEFAULT_MODEL
    ).run

    persist_headline(result)
    result
  rescue => error
    record_failure(error, stage: "headline_extraction")
    raise
  end


  def revalidate_headline(pdf_path:, institution_name:, population: nil)
    raise ArgumentError, "reviewed extractions are immutable; create a new extractor version" if financial_statement_extraction.reviewed_at.present?
    unless financial_statement_extraction.extractor_version == Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
      raise ArgumentError, "only headline extractions can be revalidated"
    end

    result = Warehouse::FinancialStatementExtraction::Pipeline.new(
      pdf_path:,
      institution_canonical_id: financial_statement_extraction.institution_canonical_id,
      institution_name:,
      document_canonical_id: financial_statement_extraction.document_canonical_id,
      asset_sha256: financial_statement_extraction.asset_sha256,
      fiscal_year_end: financial_statement_extraction.fiscal_year_end,
      population:,
      model: financial_statement_extraction.llm_model.presence || Warehouse::FinancialStatementExtraction::Pipeline::DEFAULT_MODEL
    ).revalidate(
      response: financial_statement_extraction.llm_response_snapshot,
      prompt: financial_statement_extraction.llm_prompt_snapshot&.fetch("prompt", nil),
      source_pages: financial_statement_extraction.financial_statement_facts.to_h do |fact|
        [ fact.concept, fact.source_page ]
      end
    )
    persist_headline(result)
    result
  end

  def extract_detailed(pdf_path:, institution_name:, population: nil)
    raise ArgumentError, "reviewed extractions are immutable; create a new extractor version" if financial_statement_extraction.reviewed_at.present?

    financial_statement_extraction.update!(status: "extracting", error_message: nil)
    page_locator = Warehouse::FinancialStatementExtraction::PageLocator.new(pdf_path)
    headline = financial_statement_extraction.institution_release.financial_statement_extractions
      .where(status: Warehouse::FinancialStatementExtraction::Processor::DETAIL_HEADLINE_STATUSES).find_by(
      asset_sha256: financial_statement_extraction.asset_sha256,
      extractor_version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION,
      fiscal_year_end: financial_statement_extraction.fiscal_year_end
    )
    headline_pipeline = headline && Warehouse::FinancialStatementExtraction::StoredHeadlinePipeline.new(
      extraction: headline, pdf_path:, page_locator:, allow_needs_review: headline.status == "needs_review"
    )
    result = detailed_pipeline(
      pdf_path:,
      institution_canonical_id: financial_statement_extraction.institution_canonical_id,
      institution_name:,
      document_canonical_id: financial_statement_extraction.document_canonical_id,
      asset_sha256: financial_statement_extraction.asset_sha256,
      fiscal_year_end: financial_statement_extraction.fiscal_year_end,
      population:,
      model: financial_statement_extraction.llm_model.presence || Warehouse::FinancialStatementExtraction::DetailedPipeline::DEFAULT_MODEL,
      page_locator:, headline_pipeline:
    ).run

    financial_statement_extraction.transaction do
      Warehouse::FinancialStatementFact.where(financial_statement_extraction:).delete_all
      Warehouse::FinancialStatementLineItem.where(financial_statement_extraction:).delete_all
      result.facts.each { |attributes| financial_statement_extraction.financial_statement_facts.create!(attributes) }
      result.line_items.each { |attributes| financial_statement_extraction.financial_statement_line_items.create!(attributes) }
      financial_statement_extraction.update!(
        status: result.status,
        statement_basis: result.statement_basis,
        language: result.language,
        check_results: result.checks,
        llm_prompt_snapshot: { prompt: result.prompt },
        llm_response_snapshot: result.response,
        error_message: nil
      )
    end
    result
  rescue => error
    record_failure(error, stage: "detailed_extraction")
    raise
  end

  private

  def record_failure(error, stage:)
    return if financial_statement_extraction.reviewed_at.present?

    detail = "#{error.class}: #{error.message}"
    financial_statement_extraction.update!(
      status: "failed",
      check_results: [ { id: stage, status: "fail", detail: } ],
      error_message: detail
    )
  end

  def persist_headline(result)
    financial_statement_extraction.transaction do
      Warehouse::FinancialStatementFact.where(financial_statement_extraction:).delete_all
      result.facts.each { |attributes| financial_statement_extraction.financial_statement_facts.create!(attributes) }
      financial_statement_extraction.update!(
        status: result.status,
        statement_basis: result.statement_basis,
        language: result.language,
        check_results: result.checks,
        llm_prompt_snapshot: { prompt: result.prompt },
        llm_response_snapshot: result.response,
        error_message: nil
      )
    end
  end

  def headline_pipeline(**attributes)
    fallback = Warehouse::FinancialStatementExtraction::Pipeline.new(**attributes)
    pipeline_class = deterministic_pipeline_class(attributes)
    return fallback unless pipeline_class

    deterministic = pipeline_class.new(**attributes)
    Warehouse::FinancialStatementExtraction::FallbackPipeline.new(
      primary: pipeline_class::Headline.new(deterministic), fallback:, on: pipeline_class::Unsupported
    )
  end

  def detailed_pipeline(**attributes)
    fallback = Warehouse::FinancialStatementExtraction::DetailedPipeline.new(**attributes)
    pipeline_class = deterministic_pipeline_class(attributes)
    return fallback unless pipeline_class

    Warehouse::FinancialStatementExtraction::FallbackPipeline.new(
      primary: pipeline_class.new(**attributes), fallback:, on: pipeline_class::Unsupported
    )
  end

  def deterministic_pipeline_class(attributes)
    [
      Warehouse::FinancialStatementExtraction::QuebecFormPipeline,
      Warehouse::FinancialStatementExtraction::SaskatchewanFormPipeline
    ].find { _1.applicable?(**attributes.slice(:institution_canonical_id, :fiscal_year_end)) }
  end
end
