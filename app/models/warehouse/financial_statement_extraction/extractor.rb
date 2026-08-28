class Warehouse::FinancialStatementExtraction::Extractor < ActiveRecord::AssociatedObject
  performs :extract, queue_as: :default

  def extract(pdf_path:, institution_name:, population: nil)
    raise ArgumentError, "reviewed extractions are immutable; create a new extractor version" if financial_statement_extraction.reviewed_at.present?

    financial_statement_extraction.update!(status: "extracting", error_message: nil)
    result = Warehouse::FinancialStatementExtraction::Pipeline.new(
      pdf_path:,
      institution_canonical_id: financial_statement_extraction.institution_canonical_id,
      institution_name:,
      document_canonical_id: financial_statement_extraction.document_canonical_id,
      asset_sha256: financial_statement_extraction.asset_sha256,
      fiscal_year_end: financial_statement_extraction.fiscal_year_end,
      population:,
      model: financial_statement_extraction.llm_model.presence || Warehouse::FinancialStatementExtraction::Pipeline::DEFAULT_MODEL
    ).run

    financial_statement_extraction.transaction do
      financial_statement_extraction.financial_statement_facts.delete_all
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
    result
  rescue => error
    unless financial_statement_extraction.reviewed_at.present?
      financial_statement_extraction.update!(status: "failed", error_message: "#{error.class}: #{error.message}")
    end
    raise
  end
end
