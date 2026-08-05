class Warehouse::Measure < Warehouse::Record
  include Searchable
  searchable_in realm: "kpi", record_type: "kpi"

  AGGREGATION_TYPES = %w[
    additive semi_additive average ratio median index rate part_of_whole non_aggregable unknown
  ].freeze
  FREQUENCIES = %w[annual fiscal_year quarterly monthly point_in_time irregular unknown].freeze

  belongs_to :organization, optional: true
  belongs_to :unit
  belongs_to :agent_run, optional: true
  belongs_to :numerator_measure,   class_name: "Warehouse::Measure", optional: true
  belongs_to :denominator_measure, class_name: "Warehouse::Measure", optional: true

  has_many :metric_versions,
    class_name: "Warehouse::MetricVersion",
    foreign_key: :measure_id,
    dependent: :destroy
  has_many :aliases,
    class_name: "Warehouse::MetricAlias",
    foreign_key: :measure_id,
    dependent: :destroy
  has_many :metric_compositions,
    class_name: "Warehouse::MetricComposition",
    foreign_key: :measure_id,
    dependent: :destroy
  has_many :metric_components,
    class_name: "Warehouse::MetricComponent",
    foreign_key: :measure_id,
    dependent: :destroy
  has_many :equivalence_aliases,
    -> { where(kind: "measure_equivalence") },
    class_name: "Warehouse::MetricAlias",
    foreign_key: :canonical_measure_id,
    dependent: :destroy
  has_many :extracted_observations,
    class_name: "Warehouse::ExtractedObservation",
    foreign_key: :measure_id,
    inverse_of: :measure,
    dependent: :destroy
  has_many :canonical_observations,
    class_name: "Warehouse::CanonicalObservation",
    foreign_key: :measure_id,
    inverse_of: :measure,
    dependent: :destroy
  has_many :facts,
    class_name: "Warehouse::MeasureFact",
    foreign_key: :measure_id,
    inverse_of: :measure
  has_many :measure_footnotes,
    class_name: "Warehouse::MeasureFootnote",
    foreign_key: :measure_id,
    dependent: :delete_all
  has_many :source_footnotes,
    through: :measure_footnotes
  has_many :predecessor_lineages,
    class_name: "Warehouse::MeasureLineage",
    foreign_key: :successor_id,
    inverse_of: :successor,
    dependent: :destroy
  has_many :successor_lineages,
    class_name: "Warehouse::MeasureLineage",
    foreign_key: :predecessor_id,
    inverse_of: :predecessor,
    dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: :organization_id }
  validates :canonical_name, presence: true
  validates :aggregation_type, inclusion: { in: AGGREGATION_TYPES }
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_nil: true

  scope :canonical, -> { where(organization_id: nil) }

  before_validation :normalize_service_category
  after_commit :enqueue_search_sync, on: %i[create update]

  # Resolve an org-scoped measure to its canonical equivalent via a
  # measure_equivalence alias, if one exists. Returns self otherwise.
  def canonical_equivalent
    return self if organization_id.nil?
    alias_row = aliases.measure_equivalences.where.not(canonical_measure_id: nil).first
    alias_row&.canonical_measure || self
  end

  def search_data
    jurisdiction = organization&.jurisdiction
    {
      canonical_url: "/api/v1/kpis/measures/#{id}",
      title: canonical_name,
      summary: description,
      content: [ canonical_name, description, category, service_category,
        organization&.canonical_name, unit&.symbol, frequency ].compact_blank.join("\n"),
      language: "und",
      published_at: created_at,
      source_updated_at: updated_at,
      ontology: {
        "organization_ids" => Array(organization_id),
        "organization_names" => Array(organization&.canonical_name),
        "jurisdiction_ids" => Array(jurisdiction&.id),
        "jurisdiction_codes" => Array(jurisdiction&.code),
        "jurisdiction_levels" => Array(jurisdiction&.level),
        "categories" => [ category, service_category ].compact
      },
      realm_data: {
        "kpi_measure_id" => id,
        "kpi_measure_name" => canonical_name,
        "kpi_measure_slug" => slug,
        "kpi_measure_description" => description,
        "kpi_category" => category,
        "kpi_service_category" => service_category,
        "kpi_aggregation_type" => aggregation_type,
        "kpi_frequency" => frequency,
        "kpi_higher_is_bad" => higher_is_bad,
        "kpi_unit_id" => unit_id,
        "kpi_unit_symbol" => unit&.symbol,
        "kpi_unit_kind" => unit&.kind,
        "kpi_currency_code" => unit&.currency_code,
        "kpi_last_updated_at" => updated_at
      }.compact
    }
  end

  # Strip trailing parenthetical quality-attribute tags from a service_category
  # string. Toronto budget docs append year-specific framing tags like
  # "(Reliable, Resilient)", "(Accessible, Vibrant)" — these create UI
  # fragmentation when each year picks a different combination. The clean
  # form ("Road and Sidewalk Management") is the canonical grouping key.
  def self.normalize_service_category(raw)
    return raw if raw.blank?
    raw.to_s.sub(/\s*\([^()]*\)\s*\z/, "").strip.presence
  end

  private

  def enqueue_search_sync
    Search::SyncJob.perform_later(self)
  end

  def normalize_service_category
    self.service_category = self.class.normalize_service_category(service_category)
  end
end
