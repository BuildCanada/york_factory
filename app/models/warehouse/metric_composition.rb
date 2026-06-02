class Warehouse::MetricComposition < Warehouse::Record
  self.table_name = "warehouse.metric_compositions"

  belongs_to :measure
  belongs_to :expected_total_unit, class_name: "Warehouse::Unit",
    foreign_key: :expected_total_unit_id, optional: true

  has_many :components,
    class_name: "Warehouse::MetricComponent",
    foreign_key: :composition_id,
    dependent: :destroy
  has_many :validation_results,
    class_name: "Warehouse::CompositionValidationResult",
    foreign_key: :composition_id,
    dependent: :destroy
  has_many :extracted_observations,
    class_name: "Warehouse::ExtractedObservation",
    foreign_key: :composition_id,
    dependent: :nullify
  has_many :canonical_observations,
    class_name: "Warehouse::CanonicalObservation",
    foreign_key: :composition_id,
    dependent: :nullify

  validates :composition_type, :name, presence: true
  validates :composition_type, uniqueness: { scope: :measure_id }
end
