class GeoCrosswalk < WarehouseRecord
  belongs_to :source, class_name: "GeoBoundary"
  belongs_to :target, class_name: "GeoBoundary"

  validates :source_id, uniqueness: { scope: [ :target_id, :census_year ] }
  validates :source_type, presence: true
  validates :target_type, presence: true

  scope :from_type, ->(type) { where(source_type: type) }
  scope :to_type, ->(type) { where(target_type: type) }
  scope :for_source, ->(boundary) { where(source_id: boundary.id) }
end
