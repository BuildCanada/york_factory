class Warehouse::FinancialStatementExtraction::Processor
  RERUN_POLICIES = %w[missing failed review all].freeze
  DETAIL_HEADLINE_STATUSES = %w[extracted needs_review approved].freeze
  Outcome = Data.define(:status, :stage, :extraction_id, :error)

  def initialize(release:, rerun: "missing")
    @release = release
    @rerun = rerun.to_s
    raise ArgumentError, "unsupported rerun policy #{@rerun.inspect}" unless @rerun.in?(RERUN_POLICIES)
  end

  def call(candidate)
    detailed = extraction_for(candidate, Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION)
    return outcome("skipped", "detailed", detailed.id) unless runnable?(detailed)
    return outcome("missing_asset", "source") unless candidate.pdf_path.file?

    headline = extraction_for(candidate, Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION)
    headline = run_headline(candidate, headline) if runnable?(headline)
    return outcome(headline.status, "headline", headline.id) unless headline.status.in?(DETAIL_HEADLINE_STATUSES)

    detailed = run_detailed(candidate, detailed, headline)
    outcome(detailed.status, "detailed", detailed.id)
  rescue ActiveRecord::RecordNotUnique
    outcome("concurrent_skip", "identity")
  rescue => error
    outcome("failed", "exception", nil, "#{error.class}: #{error.message}")
  end

  private

  def extraction_for(candidate, version)
    @release.financial_statement_extractions.find_or_initialize_by(
      asset_sha256: candidate.asset_sha256,
      extractor_version: version,
      fiscal_year_end: candidate.fiscal_year_end
    ) do |extraction|
      extraction.assign_attributes(base_attributes(candidate, version:))
    end
  end

  def run_headline(candidate, extraction)
    return extraction if extraction.persisted? && !runnable?(extraction)

    extraction.assign_attributes(base_attributes(
      candidate, version: Warehouse::FinancialStatementExtraction::Pipeline::EXTRACTOR_VERSION
    ))
    extraction.save!
    extraction.extractor.extract(
      pdf_path: candidate.pdf_path,
      institution_name: candidate.institution_name,
      population: candidate.population
    )
    extraction.reload
  end

  def run_detailed(candidate, extraction, headline)
    extraction.assign_attributes(base_attributes(
      candidate, version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION,
      language: headline.language, statement_basis: headline.statement_basis
    ))
    extraction.save!
    extraction.extractor.extract_detailed(
      pdf_path: candidate.pdf_path,
      institution_name: candidate.institution_name,
      population: candidate.population
    )
    extraction.reload
  end

  def base_attributes(candidate, version:, language: nil, statement_basis: "consolidated")
    {
      institution_canonical_id: candidate.institution_canonical_id,
      document_canonical_id: candidate.document_canonical_id,
      fiscal_year_end: candidate.fiscal_year_end,
      statement_basis:,
      language:,
      llm_model: model_for(version),
      status: "pending"
    }
  end

  def model_for(version)
    if version == Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION
      Warehouse::FinancialStatementExtraction::DetailedPipeline::DEFAULT_MODEL
    else
      Warehouse::FinancialStatementExtraction::Pipeline::DEFAULT_MODEL
    end
  end

  def runnable?(extraction)
    return true unless extraction.persisted?
    return false if extraction.reviewed_at?

    case @rerun
    when "missing" then extraction.status == "pending"
    when "failed" then extraction.status.in?(%w[pending failed])
    when "review" then extraction.status.in?(%w[pending failed needs_review])
    when "all" then true
    end
  end

  def outcome(status, stage, extraction_id = nil, error = nil)
    Outcome.new(status:, stage:, extraction_id:, error:)
  end
end
