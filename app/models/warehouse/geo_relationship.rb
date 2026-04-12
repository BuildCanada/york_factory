class Warehouse::GeoRelationship < Warehouse::Record
  belongs_to :da, class_name: "Warehouse::GeoBoundary"
  belongs_to :parent, class_name: "Warehouse::GeoBoundary"
  belongs_to :raw_ingestion, optional: true

  validates :relationship_type, presence: true
  validates :da_id, uniqueness: { scope: [ :parent_id, :relationship_type ] }
end
