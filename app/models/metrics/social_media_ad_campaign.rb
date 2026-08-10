class Metrics::SocialMediaAdCampaign < ApplicationRecord
  self.table_name = "metrics_social_media_ad_campaigns"

  belongs_to :account,
    class_name: "Metrics::SocialMediaAccount",
    foreign_key: :social_media_account_id,
    inverse_of: :ad_campaigns
  belongs_to :ad_account, class_name: "Metrics::SocialMediaAdAccount", optional: true
  has_many :ads,
    class_name: "Metrics::SocialMediaAd",
    foreign_key: :campaign_id,
    dependent: :nullify
  has_many :daily_metrics,
    class_name: "Metrics::SocialMediaAdCampaignDailyMetric",
    foreign_key: :campaign_id,
    dependent: :destroy

  validates :platform_campaign_id, :platform, presence: true
  validates :platform_campaign_id, uniqueness: { scope: [ :social_media_account_id, :platform ] }
end
