class Metrics::SocialMediaAdAccountDailyMetric < ApplicationRecord
  self.table_name = "metrics_social_media_ad_account_daily_metrics"

  belongs_to :ad_account, class_name: "Metrics::SocialMediaAdAccount"

  validates :date, presence: true
  validates :date, uniqueness: { scope: :ad_account_id }
end
