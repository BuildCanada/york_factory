require "set"

class Warehouse::FinancialStatementExtraction::CandidateWindow
  attr_reader :start, :stop_before, :document_ids, :excluded_document_ids

  def initialize(start: nil, stop_before: nil, document_ids: nil, excluded_document_ids: nil)
    @start = start
    @stop_before = stop_before
    @document_ids = Array(document_ids).map { Integer(_1) }.to_set
    @excluded_document_ids = Array(excluded_document_ids).map { Integer(_1) }.to_set
  end

  def before_start?(candidate)
    start.present? && candidate.document_id < start
  end

  def at_or_after_stop?(candidate)
    stop_before.present? && candidate.document_id >= stop_before
  end

  def selected?(candidate)
    document_ids.empty? || document_ids.include?(candidate.document_id)
  end

  def excluded?(candidate)
    excluded_document_ids.include?(candidate.document_id)
  end
end
