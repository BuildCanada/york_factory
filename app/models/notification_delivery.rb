class NotificationDelivery < ApplicationRecord
  CHANNELS = %w[email webhook].freeze
  STATUSES = %w[pending delivering delivered failed dead].freeze

  belongs_to :notification_batch

  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :attempt_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def claim!
    update!(status: "delivering", attempt_count: attempt_count + 1, last_error: nil)
  end

  def delivered!(at: Time.current, provider_response: {})
    update!(status: "delivered", delivered_at: at,
      provider_response: provider_response, last_error: nil)
  end

  def retry_later!(error:, at:)
    update!(status: "failed", last_error: error.to_s.truncate(2_000), next_attempt_at: at)
  end

  def dead!(error:)
    update!(status: "dead", last_error: error.to_s.truncate(2_000), next_attempt_at: nil)
  end
end
