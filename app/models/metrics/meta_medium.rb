class Metrics::MetaMedium < ApplicationRecord
  self.table_name = "metrics_meta_media"

  DAILY_SNAPSHOTS = 30
  WEEKLY_SNAPSHOTS = 16
  MONTHLY_SNAPSHOTS = 8

  belongs_to :account,
    class_name: "Metrics::MetaAccount",
    foreign_key: :meta_account_id,
    inverse_of: :media
  has_many :insights,
    class_name: "Metrics::MetaMediaInsight",
    foreign_key: :meta_medium_id,
    inverse_of: :medium,
    dependent: :destroy

  validates :platform_media_id, presence: true,
    uniqueness: { scope: :meta_account_id }

  scope :due_for_insights, ->(at = Time.current) {
    where(insights_sync_completed_at: nil)
      .where(next_insights_sync_at: ..at)
  }

  def insight_checkpoints
    return [] unless published_at

    daily = DAILY_SNAPSHOTS.times.map { |day| published_at + day.days }
    weekly_start = published_at + DAILY_SNAPSHOTS.days
    weekly = 1.upto(WEEKLY_SNAPSHOTS).map { |week| weekly_start + week.weeks }
    monthly_start = weekly.last
    monthly = 1.upto(MONTHLY_SNAPSHOTS).map { |month| monthly_start.advance(months: month) }
    daily + weekly + monthly
  end

  def next_insight_checkpoint(after:)
    insight_checkpoints.find { |checkpoint| checkpoint > after }
  end

  def schedule_initial_insights!(at: published_at || Time.current)
    return if next_insights_sync_at || insights_sync_completed_at

    update!(next_insights_sync_at: at)
  end

  def mark_insights_synced!(scheduled_for:, synced_at: Time.current)
    with_lock do
      return unless next_insights_sync_at == scheduled_for

      next_checkpoint = next_insight_checkpoint(after: synced_at)
      update!(
        last_insights_synced_at: synced_at,
        next_insights_sync_at: next_checkpoint,
        insights_sync_enqueued_at: nil,
        insights_sync_completed_at: next_checkpoint ? nil : synced_at
      )
    end
  end
end
