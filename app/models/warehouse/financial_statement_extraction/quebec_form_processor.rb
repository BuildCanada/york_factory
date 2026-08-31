class Warehouse::FinancialStatementExtraction::QuebecFormProcessor
  Outcome = Data.define(:status, :document_canonical_id, :detailed_extraction_id, :error)

  def initialize(release:)
    @release = release
  end

  def call(candidate)
    return outcome("missing_asset", candidate, nil, "archived PDF is missing") unless candidate.pdf_path.file?
    unless pipeline_class.applicable?(
      institution_canonical_id: candidate.institution_canonical_id,
      fiscal_year_end: candidate.fiscal_year_end
    )
      return outcome("unsupported", candidate, nil, "deterministic form parser does not apply")
    end

    detailed = extraction(candidate, Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION)
    return outcome("skipped", candidate, detailed.id) if detailed.reviewed_at?
    if detailed.persisted? && detailed.status == "extracted" &&
        detailed.llm_response_snapshot&.fetch("parser", nil) == parser_version
      return outcome("skipped", candidate, detailed.id)
    end

    result = pipeline_class.new(
      pdf_path: candidate.pdf_path,
      institution_canonical_id: candidate.institution_canonical_id,
      institution_name: candidate.institution_name,
      document_canonical_id: candidate.document_canonical_id,
      asset_sha256: candidate.asset_sha256,
      fiscal_year_end: candidate.fiscal_year_end,
      population: candidate.population
    ).run
    headline = extraction(candidate, Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION)
    persist(candidate, headline, detailed, result)
    outcome("extracted", candidate, detailed.id)
  rescue => error
    if error.is_a?(pipeline_class::Unsupported)
      record_failure(candidate, detailed, error, check_id: "deterministic_parser", parser_outcome: "unsupported")
      outcome("unsupported", candidate, detailed&.id, error.message)
    else
      record_failure(candidate, detailed, error, check_id: "parser_execution", parser_outcome: "failed")
      outcome("failed", candidate, detailed&.id, "#{error.class}: #{error.message}")
    end
  end

  private

  def extraction(candidate, version)
    @release.financial_statement_extractions.find_or_initialize_by(
      asset_sha256: candidate.asset_sha256,
      extractor_version: version,
      fiscal_year_end: candidate.fiscal_year_end
    ) do |row|
      row.assign_attributes(
        institution_canonical_id: candidate.institution_canonical_id,
        document_canonical_id: candidate.document_canonical_id,
        statement_basis: "consolidated",
        language: nil,
        llm_model: parser_version,
        status: "pending"
      )
    end
  end

  def persist(candidate, headline, detailed, result)
    flags = result.response.fetch("headline")
    @release.transaction do
      [ headline, detailed ].each do |row|
        raise ArgumentError, "reviewed extraction is immutable" if row.reviewed_at?

        row.assign_attributes(
          institution_canonical_id: candidate.institution_canonical_id,
          document_canonical_id: candidate.document_canonical_id,
          asset_sha256: candidate.asset_sha256,
          fiscal_year_end: candidate.fiscal_year_end,
          statement_basis: result.statement_basis,
          language: result.language,
          llm_model: parser_version,
          status: "extracted", check_results: result.checks,
          llm_prompt_snapshot: { prompt: nil }, error_message: nil
        )
        row.llm_response_snapshot = response_for(row, result, flags)
        row.save!
        Warehouse::FinancialStatementFact.where(financial_statement_extraction: row).delete_all
        result.facts.each { |attributes| row.financial_statement_facts.create!(attributes) }
      end
      Warehouse::FinancialStatementLineItem.where(financial_statement_extraction: detailed).delete_all
      result.line_items.each { |attributes| detailed.financial_statement_line_items.create!(attributes) }
    end
  end

  def response_for(extraction, result, flags)
    if extraction.extractor_version == Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
      flags.merge(
        "parser" => parser_version,
        "fiscal_year" => extraction.fiscal_year_end.year,
        "language" => result.language,
        "statement_basis" => result.statement_basis
      )
    else
      result.response
    end
  end

  def record_failure(candidate, extraction, error, check_id:, parser_outcome:)
    return unless extraction
    return if extraction.reviewed_at?
    if extraction.persisted? && extraction.status == "extracted" &&
        extraction.llm_response_snapshot&.fetch("parser", nil) == parser_version
      return
    end

    extraction.assign_attributes(
      institution_canonical_id: candidate.institution_canonical_id,
      document_canonical_id: candidate.document_canonical_id,
      asset_sha256: candidate.asset_sha256,
      fiscal_year_end: candidate.fiscal_year_end,
      statement_basis: "consolidated",
      language: nil,
      llm_model: parser_version,
      status: "failed",
      check_results: [ { id: check_id, status: "fail", detail: error.message } ],
      llm_prompt_snapshot: { prompt: nil },
      llm_response_snapshot: { "parser" => parser_version, "outcome" => parser_outcome },
      error_message: "#{error.class}: #{error.message}"
    )
    extraction.save!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def outcome(status, candidate, extraction_id = nil, error = nil)
    Outcome.new(status:, document_canonical_id: candidate.document_canonical_id,
      detailed_extraction_id: extraction_id, error:)
  end

  def pipeline_class = Warehouse::FinancialStatementExtraction::QuebecFormPipeline
  def parser_version = pipeline_class::PARSER_VERSION
end
