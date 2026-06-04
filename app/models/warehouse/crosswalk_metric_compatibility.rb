class Warehouse::CrosswalkMetricCompatibility < Warehouse::Record
  COMPATIBILITIES = %w[recommended acceptable risky not_allowed].freeze

  self.table_name = "warehouse.crosswalk_metric_compatibility"

  belongs_to :crosswalk_set, class_name: "Warehouse::GeographyCrosswalkSet",
    foreign_key: :crosswalk_set_id
  belongs_to :measure

  validates :compatibility, inclusion: { in: COMPATIBILITIES }
end
