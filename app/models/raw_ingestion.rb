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
  has_object :corporate_normalizer
  has_object :orgbook_bc_normalizer
  has_object :quebec_registry_normalizer
  has_object :odbiz_normalizer
  has_object :oda_normalizer
  has_object :ontario_obr_scraper
  has_object :alberta_cores_scraper
  has_object :saskatchewan_isc_scraper
end
