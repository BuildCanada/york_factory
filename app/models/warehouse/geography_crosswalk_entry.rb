class Warehouse::GeographyCrosswalkEntry < Warehouse::Record
  RELATIONSHIP_KINDS = %w[
    equivalent contains contained_by split merged overlaps allocated estimated manual
  ].freeze

  self.table_name = "warehouse.geography_crosswalk_entries"

  belongs_to :crosswalk_set, class_name: "Warehouse::GeographyCrosswalkSet",
    foreign_key: :crosswalk_set_id
  belongs_to :from_geo, class_name: "Warehouse::GeoBoundary"
  belongs_to :to_geo,   class_name: "Warehouse::GeoBoundary"

  validates :weight,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
  validates :relationship_type, presence: true, inclusion: { in: RELATIONSHIP_KINDS }
end
