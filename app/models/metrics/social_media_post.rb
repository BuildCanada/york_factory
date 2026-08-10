class Metrics::SocialMediaPost < ApplicationRecord
  self.table_name = "metrics_social_media_posts"

  belongs_to :account,
    class_name: "Metrics::SocialMediaAccount",
    foreign_key: :social_media_account_id,
    inverse_of: :posts
  belongs_to :social_post, optional: true
  has_many :metric_snapshots,
    class_name: "Metrics::SocialMediaPostMetricSnapshot",
    foreign_key: :social_media_post_id,
    inverse_of: :post,
    dependent: :destroy

  validates :zernio_post_id, :platform, :status, presence: true
  validates :zernio_post_id, uniqueness: { scope: :social_media_account_id }

  def latest_metric_snapshot
    metric_snapshots.order(observed_at: :desc).first
  end
end
