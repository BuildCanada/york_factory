class GeoBoundary < WarehouseRecord
  BOUNDARY_TYPES = %w[da ct csd fsa fed ped ward pr cd er cma popctr school_board_ward].freeze

  enum :boundary_type, BOUNDARY_TYPES.index_by(&:itself)

  belongs_to :raw_ingestion, optional: true

  has_many :da_relationships, class_name: "GeoRelationship", foreign_key: :da_id, dependent: :destroy, inverse_of: :da
  has_many :parent_relationships, class_name: "GeoRelationship", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent

  has_many :source_crosswalks, class_name: "GeoCrosswalk", foreign_key: :source_id, dependent: :destroy, inverse_of: :source
  has_many :target_crosswalks, class_name: "GeoCrosswalk", foreign_key: :target_id, dependent: :destroy, inverse_of: :target

  validates :boundary_type, presence: true
  validates :geo_uid, presence: true, uniqueness: { scope: [ :boundary_type, :census_year ] }

  scope :by_type, ->(type) { where(boundary_type: type) }
  scope :in_province, ->(code) { where(province_code: code) }
  scope :search_name, ->(q) { where("name_en ILIKE :q OR name_fr ILIKE :q", q: "%#{sanitize_sql_like(q)}%") }
end
