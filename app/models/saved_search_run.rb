class SavedSearchRun < ApplicationRecord
  STATUSES = %w[pending running succeeded failed].freeze

  belongs_to :saved_search

  validates :scheduled_for, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :from_sequence, :to_sequence, :query_count, :matched_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :sequence_window_is_ordered

  scope :recent_first, -> { order(scheduled_for: :desc) }

  def start!(at: Time.current)
    update!(status: "running", started_at: at, finished_at: nil, error: nil)
  end

  def succeed!(at: Time.current, **attributes)
    update!(attributes.merge(status: "succeeded", finished_at: at,
      duration_ms: elapsed_ms(at), error: nil))
  end

  def fail!(error:, at: Time.current)
    update!(status: "failed", error: error.to_s.truncate(2_000), finished_at: at,
      duration_ms: elapsed_ms(at))
  end

  private

  def sequence_window_is_ordered
    errors.add(:to_sequence, "must not precede from_sequence") if to_sequence < from_sequence
  end

  def elapsed_ms(at)
    return unless started_at

    ((at - started_at) * 1_000).round
  end
end
