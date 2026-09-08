class Metrics::SubstackPublication < ApplicationRecord
  self.table_name = "metrics_substack_publications"

  has_many :posts,
    class_name: "Metrics::SubstackPost",
    foreign_key: :substack_publication_id,
    inverse_of: :publication,
    dependent: :destroy

  validates :account_key, :url, presence: true
  validates :account_key, uniqueness: true
  validates :publication_id, uniqueness: true, allow_nil: true
end
