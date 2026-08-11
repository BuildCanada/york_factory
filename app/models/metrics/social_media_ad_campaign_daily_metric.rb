class Metrics::SocialMediaAdCampaignDailyMetric < ApplicationRecord
  self.table_name = "metrics_social_media_ad_campaign_daily_metrics"

  belongs_to :campaign, class_name: "Metrics::SocialMediaAdCampaign"

  validates :date, presence: true
  validates :date, uniqueness: { scope: :campaign_id }
end
