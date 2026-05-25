class Warehouse::KpiDocument < Warehouse::Record
  PUBLISHED_AT_SOURCES = %w[
    pdf_metadata http_last_modified council_schedule discovered_at_fallback manual
  ].freeze

  belongs_to :jurisdiction
  belongs_to :organization, optional: true
  belongs_to :raw_ingestion, optional: true
  belongs_to :agent_run, optional: true
  has_many :citations,
    class_name: "Warehouse::MeasureCitation",
    foreign_key: :document_id,
    inverse_of: :document,
    dependent: :restrict_with_error

  validates :doc_url, presence: true, uniqueness: true
  validates :fiscal_year, presence: true
  validates :published_at_source,
    inclusion: { in: PUBLISHED_AT_SOURCES },
    allow_nil: true
end
