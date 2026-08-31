class Warehouse::CensusProfile < Warehouse::Record
  GEO_LEVELS = %w[csd cd pr da].freeze

  validates :census_year, numericality: { only_integer: true, greater_than: 0 }
  validates :geo_level, inclusion: { in: GEO_LEVELS }
  validates :geo_uid, :source_url, :retrieved_at, presence: true
  validates :population, numericality: { only_integer: true, greater_than: 0 }
  validates :area_sq_km, numericality: { greater_than: 0 }, allow_nil: true
  validates :population_density_per_sq_km, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :source_sha256, format: { with: /\A[0-9a-f]{64}\z/ },
    uniqueness: { scope: [ :census_year, :geo_level, :geo_uid ] }
end
