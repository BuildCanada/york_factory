class Warehouse::Measure < Warehouse::Record
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

  # Resolve an org-scoped measure to its canonical equivalent via a
  # measure_equivalence alias, if one exists. Returns self otherwise.
  def canonical_equivalent
    return self if organization_id.nil?
    alias_row = aliases.measure_equivalences.where.not(canonical_measure_id: nil).first
    alias_row&.canonical_measure || self
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

  def normalize_service_category
    self.service_category = self.class.normalize_service_category(service_category)
  end
end
