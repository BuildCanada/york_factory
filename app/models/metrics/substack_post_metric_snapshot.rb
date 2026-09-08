class Metrics::SubstackPostMetricSnapshot < ApplicationRecord
  self.table_name = "metrics_substack_post_metric_snapshots"

  SNAPSHOT_TYPES = %w[current first_week_daily].freeze

  belongs_to :post,
    class_name: "Metrics::SubstackPost",
    foreign_key: :substack_post_id,
    inverse_of: :metric_snapshots

  validates :snapshot_type, inclusion: { in: SNAPSHOT_TYPES }
  validates :observed_at, :scraped_at, presence: true
  validates :observed_at, uniqueness: { scope: %i[substack_post_id snapshot_type] }
end
