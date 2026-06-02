class Warehouse::CompositionValidationResult < Warehouse::Record
  STATUSES   = %w[ok warn fail].freeze
  SEVERITIES = %w[low medium high critical].freeze
  VALIDATION_TYPES = %w[
    components_sum_to_total
    components_sum_to_100
    missing_total
    missing_component
    new_component
    other_component_too_large
    unit_mismatch_between_components
    component_not_mutually_exclusive
  ].freeze

  self.table_name = "warehouse.composition_validation_results"

  belongs_to :measure
  belongs_to :composition, class_name: "Warehouse::MetricComposition"
  belongs_to :observed_organization, class_name: "Warehouse::Organization", optional: true
  belongs_to :geo_boundary, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }, allow_nil: true
  validates :validation_type, presence: true
end
