class Warehouse::MetricComponent < Warehouse::Record
  self.table_name = "warehouse.metric_components"

  belongs_to :measure
  belongs_to :composition, class_name: "Warehouse::MetricComposition", optional: true
  belongs_to :parent_component, class_name: "Warehouse::MetricComponent", optional: true

  has_many :child_components,
    class_name: "Warehouse::MetricComponent",
    foreign_key: :parent_component_id
  has_many :outbound_relationships,
    class_name: "Warehouse::MetricComponentRelationship",
    foreign_key: :from_component_id,
    dependent: :destroy
  has_many :inbound_relationships,
    class_name: "Warehouse::MetricComponentRelationship",
    foreign_key: :to_component_id,
    dependent: :destroy

  validates :component_type, :component_name, presence: true
end
