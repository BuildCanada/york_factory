class Metrics::SocialMediaAccount < ApplicationRecord
  self.table_name = "metrics_social_media_accounts"

  has_many :posts,
    class_name: "Metrics::SocialMediaPost",
    foreign_key: :social_media_account_id,
    inverse_of: :account,
    dependent: :destroy
  has_many :metric_snapshots,
    class_name: "Metrics::SocialMediaAccountMetricSnapshot",
    foreign_key: :social_media_account_id,
    inverse_of: :account,
    dependent: :destroy

  validates :zernio_account_id, :zernio_profile_id, :profile_name, :platform,
    :account_key, :username, presence: true
  validates :zernio_account_id, uniqueness: true

  def link_existing_metrics!
    klass = metrics_class
    return unless klass

    klass.where(account: account_key).update_all(social_media_account_id: id)
  end

  private

  def metrics_class
    {
      "twitter" => Metrics::TwitterStat,
      "linkedin" => Metrics::LinkedinStat,
      "tiktok" => Metrics::TiktokStat,
      "instagram" => Metrics::InstagramStat
    }[platform]
  end
end
