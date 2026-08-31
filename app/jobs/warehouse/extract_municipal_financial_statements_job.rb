class Warehouse::ExtractMunicipalFinancialStatementsJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default
  self.resume_errors_after_advancing = false

  CIRCUIT_WINDOW = 20
  MAX_FAILURE_RATE = 0.8
  MAX_CONSECUTIVE_MISSING_ASSETS = 3
  FAILURE_STATUSES = %w[failed missing_asset].freeze

  class CircuitOpen < StandardError; end

  def perform(release_version, province:, years: nil, institution_ids: nil,
    limit: nil, rerun: "missing", asset_root: nil)
    @release = Warehouse::InstitutionRelease.find_by!(version: release_version)
    @candidate_set = candidate_set(
      province:, years:, institution_ids:, asset_root:
    )
    unless @candidate_set.asset_root.directory?
      raise CircuitOpen, "asset root is unavailable: #{@candidate_set.asset_root}"
    end
    @processor = processor(rerun:)
    @limit = Integer(limit) if limit
    @attempted = 0
    @recent_outcomes = []
    @consecutive_missing_assets = 0

    step :extract_statements do |step|
      @candidate_set.each(start: step.cursor) do |candidate|
        result = @processor.call(candidate)
        log_result(candidate, result)
        track_result!(result)
        @attempted += 1 unless result.status == "skipped"
        step.advance! from: candidate.document_id
        check_circuit!
        break if @limit && @attempted >= @limit
      end
    end
  end

  private

  def candidate_set(province:, years:, institution_ids:, asset_root:)
    options = {
      release: @release, provinces: [ province ], years:, institution_ids:
    }
    options[:asset_root] = asset_root if asset_root.present?
    Warehouse::FinancialStatementExtraction::CandidateSet.new(**options)
  end

  def processor(rerun:)
    Warehouse::FinancialStatementExtraction::Processor.new(release: @release, rerun:)
  end

  def track_result!(result)
    @recent_outcomes << result.status
    @recent_outcomes.shift while @recent_outcomes.length > CIRCUIT_WINDOW
    @consecutive_missing_assets = if result.status == "missing_asset"
      @consecutive_missing_assets + 1
    else
      0
    end
  end

  def check_circuit!
    if @consecutive_missing_assets >= MAX_CONSECUTIVE_MISSING_ASSETS
      raise CircuitOpen, "#{@consecutive_missing_assets} consecutive archived assets are missing"
    end
    return unless @recent_outcomes.length == CIRCUIT_WINDOW

    failures = @recent_outcomes.count { _1.in?(FAILURE_STATUSES) }
    if failures.fdiv(CIRCUIT_WINDOW) >= MAX_FAILURE_RATE
      raise CircuitOpen, "#{failures} of the last #{CIRCUIT_WINDOW} statements failed"
    end
  end

  def log_result(candidate, result)
    payload = {
      event: "municipal_financial_statement_extraction",
      document_id: candidate.document_canonical_id,
      fiscal_year: candidate.fiscal_year_end.year,
      status: result.status,
      stage: result.stage,
      extraction_id: result.extraction_id,
      error: result.error
    }.compact
    Rails.logger.info(payload.to_json)
  end
end
