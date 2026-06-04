class Warehouse::AlertEvent < Warehouse::Record
  self.table_name = "warehouse.alert_events"

  belongs_to :alert
  belongs_to :canonical_observation,
    class_name: "Warehouse::CanonicalObservation",
    optional: true
end
