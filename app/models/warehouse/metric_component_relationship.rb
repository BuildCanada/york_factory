class Warehouse::MetricComponentRelationship < Warehouse::Record
  RELATIONSHIP_KINDS = %w[
    renamed_to split_into merged_into reclassified_as equivalent_to parent_of child_of
  ].freeze

  self.table_name = "warehouse.metric_component_relationships"

  belongs_to :from_component, class_name: "Warehouse::MetricComponent"
  belongs_to :to_component,   class_name: "Warehouse::MetricComponent"
  belongs_to :source, optional: true

  validates :relationship_type, presence: true, inclusion: { in: RELATIONSHIP_KINDS }
  validate  :components_distinct

  private

  def components_distinct
    errors.add(:to_component_id, "must differ from from_component_id") if from_component_id == to_component_id
  end
end
