class Search::SourceFetch < ApplicationRecord
  STATUSES = %w[pending running succeeded failed not_modified].freeze

  belongs_to :source,
    class_name: "Search::Source",
    foreign_key: :search_source_id,
    inverse_of: :fetches

  validates :status, inclusion: { in: STATUSES }
  validates :items_discovered,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent_first, -> { order(created_at: :desc) }

  def start!(at: Time.current)
    update!(status: "running", started_at: at, finished_at: nil, error: nil)
  end

  def succeed!(status: "succeeded", at: Time.current, **attributes)
    raise ArgumentError, "invalid successful status" unless %w[succeeded not_modified].include?(status)

    transaction do
      update!(attributes.merge(status: status, finished_at: at, duration_ms: elapsed_ms(at)))
      source.update!(
        last_succeeded_at: at,
        consecutive_failures: 0,
        next_fetch_at: at + source.cadence_seconds.seconds
      )
    end
    self
  end

  def fail!(error:, at: Time.current, **attributes)
    transaction do
      update!(attributes.merge(status: "failed", error: error.to_s.truncate(2_000),
        finished_at: at, duration_ms: elapsed_ms(at)))
      source.update!(
        last_failed_at: at,
        consecutive_failures: source.consecutive_failures + 1,
        next_fetch_at: at + source.cadence_seconds.seconds
      )
    end
    self
  end

  private

  def elapsed_ms(at)
    return unless started_at

    ((at - started_at) * 1_000).round
  end
end
