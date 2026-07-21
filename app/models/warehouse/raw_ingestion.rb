class Warehouse::RawIngestion < Warehouse::Record
  belongs_to :source
  has_many :lineage_entries, dependent: :destroy
  has_many :kpi_documents, dependent: :nullify

  enum :status, { pending: "pending", complete: "complete", partial: "partial", failed: "failed" }

  validates :fetched_at, presence: true
  validates :raw_file_path, presence: true
  validates :checksum, presence: true, uniqueness: { scope: :source_id }

  has_object :infobase_loader
  has_object :estimates_normalizer
  has_object :lobbying_normalizer
  has_object :boundary_loader
  has_object :relationship_loader
  has_object :population_loader
  has_object :address_loader
  has_object :toronto_kpis_v1_loader
  has_object :world_bank_econ_loader
  has_object :oecd_sdmx_loader
  has_object :statcan_econ_loader
  has_object :owid_econ_loader
  has_object :ircc_admissions_loader
end
