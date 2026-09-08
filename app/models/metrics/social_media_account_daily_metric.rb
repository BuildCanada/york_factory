class Metrics::SocialMediaAccountDailyMetric < ApplicationRecord
  self.table_name = "metrics_social_media_account_daily_metrics"

  belongs_to :account,
    class_name: "Metrics::SocialMediaAccount",
    foreign_key: :social_media_account_id,
    inverse_of: :daily_metrics

  validates :date, :scraped_at, presence: true
  validates :date, uniqueness: { scope: :social_media_account_id }
end
