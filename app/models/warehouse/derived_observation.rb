class Warehouse::DerivedObservation < Warehouse::Record
  DERIVATION_METHODS = %w[
    crosswalk_allocation aggregation ratio_recompute definition_normalization rebase manual
  ].freeze

  self.table_name = "warehouse.derived_observations"

  belongs_to :measure
  belongs_to :from_canonical_observation,
    class_name: "Warehouse::CanonicalObservation",
    optional: true
  belongs_to :crosswalk_set,
    class_name: "Warehouse::GeographyCrosswalkSet",
    foreign_key: :crosswalk_set_id,
    optional: true
  belongs_to :original_geo, class_name: "Warehouse::GeoBoundary", optional: true
  belongs_to :derived_geo,  class_name: "Warehouse::GeoBoundary", optional: true
  belongs_to :unit, optional: true

  validates :derivation_method, presence: true, inclusion: { in: DERIVATION_METHODS }
  validates :measurement_year, presence: true
  validates :confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
end
