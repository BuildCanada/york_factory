class Metrics::MetaAccountInsight < ApplicationRecord
  self.table_name = "metrics_meta_account_insights"

  belongs_to :account,
    class_name: "Metrics::MetaAccount",
    foreign_key: :meta_account_id,
    inverse_of: :insights

  validates :metric_name, :observed_at, presence: true
  validates :observed_at, uniqueness: {
    scope: %i[meta_account_id metric_name period]
  }
end
