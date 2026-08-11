class Metrics::SocialMediaAdDailyMetric < ApplicationRecord
  self.table_name = "metrics_social_media_ad_daily_metrics"

  belongs_to :ad, class_name: "Metrics::SocialMediaAd"

  validates :date, presence: true
  validates :date, uniqueness: { scope: :ad_id }
end
