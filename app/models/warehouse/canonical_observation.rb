class Warehouse::CanonicalObservation < Warehouse::Record
  STATUSES     = %w[reported estimated revised final].freeze
  VALUE_TYPES  = Warehouse::ExtractedObservation::VALUE_TYPES
  PERIOD_BASES = Warehouse::ExtractedObservation::PERIOD_BASES

  self.table_name = "warehouse.canonical_observations"

  belongs_to :extracted_observation, class_name: "Warehouse::ExtractedObservation"
  belongs_to :measure, touch: true
  belongs_to :metric_version, class_name: "Warehouse::MetricVersion", optional: true
  belongs_to :composition, class_name: "Warehouse::MetricComposition", optional: true
  belongs_to :component, class_name: "Warehouse::MetricComponent", optional: true
  belongs_to :document, class_name: "Warehouse::KpiDocument"
  belongs_to :unit, optional: true

  belongs_to :reporting_organization,
    class_name: "Warehouse::Organization", optional: true
  belongs_to :responsible_organization,
    class_name: "Warehouse::Organization", optional: true
  belongs_to :observed_organization,
    class_name: "Warehouse::Organization", optional: true

  belongs_to :geo_boundary, optional: true
  belongs_to :jurisdiction, optional: true

  validates :measurement_year, presence: true
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }
  validates :period_basis, presence: true, inclusion: { in: PERIOD_BASES }
  validates :status, inclusion: { in: STATUSES }

  scope :reported, -> { where(status: "reported") }
  scope :final, -> { where(status: "final") }
end
