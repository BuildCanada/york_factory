class Warehouse::GeographyCrosswalkSet < Warehouse::Record
  WEIGHT_BASES = %w[
    area population dwellings households business_count employment road_length
    property_assessment manual exact_containment unknown
  ].freeze

  self.table_name = "warehouse.geography_crosswalk_sets"

  belongs_to :source, optional: true

  has_many :entries,
    class_name: "Warehouse::GeographyCrosswalkEntry",
    foreign_key: :crosswalk_set_id,
    dependent: :destroy
  has_many :metric_compatibilities,
    class_name: "Warehouse::CrosswalkMetricCompatibility",
    foreign_key: :crosswalk_set_id,
    dependent: :destroy
  has_many :derived_observations,
    class_name: "Warehouse::DerivedObservation",
    foreign_key: :crosswalk_set_id,
    dependent: :nullify

  validates :name, :method, :from_code_system, :to_code_system, presence: true
  validates :weight_basis, inclusion: { in: WEIGHT_BASES }

  def compatibility_for(measure)
    metric_compatibilities.find_by(measure_id: measure.id)&.compatibility
  end
end
