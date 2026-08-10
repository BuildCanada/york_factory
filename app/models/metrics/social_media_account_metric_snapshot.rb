class Metrics::SocialMediaAccountMetricSnapshot < ApplicationRecord
  self.table_name = "metrics_social_media_account_metric_snapshots"

  belongs_to :account,
    class_name: "Metrics::SocialMediaAccount",
    foreign_key: :social_media_account_id,
    inverse_of: :metric_snapshots

  validates :observed_at, :scraped_at, presence: true
  validates :observed_at, uniqueness: { scope: :social_media_account_id }
end
