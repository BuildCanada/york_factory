class Metrics::MetaMedium < ApplicationRecord
  self.table_name = "metrics_meta_media"

  belongs_to :account,
    class_name: "Metrics::MetaAccount",
    foreign_key: :meta_account_id,
    inverse_of: :media
  has_many :insights,
    class_name: "Metrics::MetaMediaInsight",
    foreign_key: :meta_medium_id,
    inverse_of: :medium,
    dependent: :destroy

  validates :platform_media_id, presence: true,
    uniqueness: { scope: :meta_account_id }
end
