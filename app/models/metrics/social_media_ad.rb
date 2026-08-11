class Metrics::SocialMediaAd < ApplicationRecord
  self.table_name = "metrics_social_media_ads"

  belongs_to :account,
    class_name: "Metrics::SocialMediaAccount",
    foreign_key: :social_media_account_id,
    inverse_of: :ads
  belongs_to :ad_account, class_name: "Metrics::SocialMediaAdAccount", optional: true
  belongs_to :campaign, class_name: "Metrics::SocialMediaAdCampaign", optional: true
  has_many :daily_metrics,
    class_name: "Metrics::SocialMediaAdDailyMetric",
    foreign_key: :ad_id,
    dependent: :destroy

  validates :zernio_ad_id, :platform, presence: true
  validates :zernio_ad_id, uniqueness: true
end
