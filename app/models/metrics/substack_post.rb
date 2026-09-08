class Metrics::SubstackPost < ApplicationRecord
  self.table_name = "metrics_substack_posts"

  DAILY_SYNC_DAYS = 7
  WEEKLY_SYNC_INTERVAL = 7.days

  belongs_to :publication,
    class_name: "Metrics::SubstackPublication",
    foreign_key: :substack_publication_id,
    inverse_of: :posts
  belongs_to :feed_post,
    class_name: "::SubstackPost",
    foreign_key: :feed_substack_post_id,
    optional: true
  has_many :metric_snapshots,
    class_name: "Metrics::SubstackPostMetricSnapshot",
    foreign_key: :substack_post_id,
    inverse_of: :post,
    dependent: :destroy

  validates :substack_post_id, presence: true,
    uniqueness: { scope: :substack_publication_id }

  scope :due_for_details, ->(at = Time.current) {
    where(published: true).where(next_details_sync_at: ..at)
  }

  def schedule_initial_details!(at: published_at || Time.current)
    return if next_details_sync_at

    update!(next_details_sync_at: at)
  end

  def next_detail_checkpoint(after:)
    return after + WEEKLY_SYNC_INTERVAL unless published_at

    daily = DAILY_SYNC_DAYS.times.map { |day| published_at + day.days }
    daily.find { |checkpoint| checkpoint > after } || next_weekly_checkpoint(after: after)
  end

  def mark_details_synced!(scheduled_for:, synced_at: Time.current)
    with_lock do
      return unless next_details_sync_at == scheduled_for

      update!(
        details_synced_at: synced_at,
        next_details_sync_at: next_detail_checkpoint(after: synced_at),
        details_sync_enqueued_at: nil
      )
    end
  end

  private

  def next_weekly_checkpoint(after:)
    weekly_start = published_at + DAILY_SYNC_DAYS.days
    return weekly_start if weekly_start > after

    elapsed_weeks = ((after - weekly_start) / WEEKLY_SYNC_INTERVAL).floor + 1
    weekly_start + elapsed_weeks.weeks
  end
end
