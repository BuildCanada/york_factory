class Metrics::MetaMediaInsight < ApplicationRecord
  self.table_name = "metrics_meta_media_insights"

  belongs_to :medium,
    class_name: "Metrics::MetaMedium",
    foreign_key: :meta_medium_id,
    inverse_of: :insights

  validates :metric_name, :observed_at, presence: true
  validates :observed_at, uniqueness: {
    scope: %i[meta_medium_id metric_name period]
  }
end
