class Warehouse::KpiDocument < Warehouse::Record
  PUBLISHED_AT_SOURCES = %w[
    pdf_metadata http_last_modified council_schedule discovered_at_fallback manual
  ].freeze

  belongs_to :jurisdiction
  belongs_to :organization, optional: true
  belongs_to :raw_ingestion, optional: true
  belongs_to :agent_run, optional: true
  has_many :extracted_observations,
    class_name: "Warehouse::ExtractedObservation",
    foreign_key: :document_id,
    inverse_of: :document,
    dependent: :restrict_with_error
  has_many :canonical_observations,
    class_name: "Warehouse::CanonicalObservation",
    foreign_key: :document_id,
    inverse_of: :document,
    dependent: :restrict_with_error
  has_many :source_footnotes,
    class_name: "Warehouse::SourceFootnote",
    foreign_key: :document_id,
    inverse_of: :document,
    dependent: :delete_all

  validates :doc_url, presence: true, uniqueness: true
  validates :fiscal_year, presence: true
  validates :published_at_source,
    inclusion: { in: PUBLISHED_AT_SOURCES },
    allow_nil: true
end
