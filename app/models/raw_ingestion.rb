class RawIngestion < ApplicationRecord
  belongs_to :source
  has_many :lineage_entries, dependent: :destroy

  enum :status, { pending: "pending", complete: "complete", partial: "partial", failed: "failed" }

  validates :fetched_at, presence: true
  validates :raw_file_path, presence: true
  validates :checksum, presence: true, uniqueness: { scope: :source_id }

  has_object :infobase_loader
  has_object :estimates_normalizer
  has_object :lobbying_normalizer
end
