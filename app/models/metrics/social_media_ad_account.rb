class Metrics::SocialMediaAdAccount < ApplicationRecord
  self.table_name = "metrics_social_media_ad_accounts"

  belongs_to :account,
    class_name: "Metrics::SocialMediaAccount",
    foreign_key: :social_media_account_id,
    inverse_of: :ad_accounts
  has_many :campaigns,
    class_name: "Metrics::SocialMediaAdCampaign",
    foreign_key: :ad_account_id,
    dependent: :nullify
  has_many :ads,
    class_name: "Metrics::SocialMediaAd",
    foreign_key: :ad_account_id,
    dependent: :nullify
  has_many :daily_metrics,
    class_name: "Metrics::SocialMediaAdAccountDailyMetric",
    foreign_key: :ad_account_id,
    dependent: :destroy

  validates :platform_ad_account_id, :platform, presence: true
  validates :platform_ad_account_id, uniqueness: { scope: :social_media_account_id }
end
