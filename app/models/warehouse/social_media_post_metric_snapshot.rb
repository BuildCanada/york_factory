class Warehouse::SocialMediaPostMetricSnapshot < Warehouse::Record
  self.table_name = "warehouse.social_media_post_metric_snapshots"

  belongs_to :post,
    class_name: "Warehouse::SocialMediaPost",
    foreign_key: :social_media_post_id,
    inverse_of: :metric_snapshots

  validates :observed_at, :scraped_at, presence: true
  validates :observed_at, uniqueness: { scope: :social_media_post_id }
end
