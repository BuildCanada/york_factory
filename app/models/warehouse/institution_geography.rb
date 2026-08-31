class Warehouse::InstitutionGeography < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  ROLES = %w[governs administers serves headquartered_in].freeze
  MATCH_METHODS = %w[
    legacy authoritative_crosswalk source_assertion exact_identifier exact_name jurisdictional_fallback
  ].freeze

  belongs_to :institution
  belongs_to :institution_geography_snapshot
  belongs_to :institution_source, class_name: "Warehouse::InstitutionSource", optional: true

  validates :role, inclusion: { in: ROLES }
  validates :match_method, inclusion: { in: MATCH_METHODS }
  validates :confidence, numericality: { in: 0..1 }, allow_nil: true
  validates :valid_to, comparison: { greater_than_or_equal_to: :valid_from }, if: -> { valid_from && valid_to }
  validates :institution_geography_snapshot_id,
    uniqueness: { scope: [ :institution_release_id, :institution_id, :role ] }
end
