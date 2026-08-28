class Warehouse::InstitutionGeographySnapshot < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  CANONICAL_ID_FORMAT = /\Aca\/geography\/[a-z0-9]+(?:-[a-z0-9]+)*\/[a-z0-9]+(?:-[a-z0-9]+)*\z/
  AUTHORITY_STATUSES = %w[legacy not_applicable verified provisional unresolved].freeze

  has_many :institution_geographies, dependent: :restrict_with_error

  validates :canonical_id,
    presence: true,
    uniqueness: { scope: :institution_release_id },
    format: { with: CANONICAL_ID_FORMAT }
  validates :code_system, :geo_uid, :boundary_type, :census_year, presence: true
  validates :authority_status, inclusion: { in: AUTHORITY_STATUSES }
  validates :geo_uid,
    uniqueness: { scope: [ :institution_release_id, :boundary_type, :census_year ] }
  validate :canonical_id_matches_attributes

  def self.canonical_id_for(boundary_type:, census_year:, geo_uid:)
    type = boundary_type.to_s.tr("_", "-").downcase
    uid = geo_uid.to_s.downcase
    "ca/geography/#{type}-#{Integer(census_year)}/#{uid}"
  end

  private

  def canonical_id_matches_attributes
    return if boundary_type.blank? || census_year.blank? || geo_uid.blank?
    return if canonical_id == self.class.canonical_id_for(
      boundary_type: boundary_type,
      census_year: census_year,
      geo_uid: geo_uid
    )

    errors.add(:canonical_id, "must match the geography type, vintage, and UID")
  end
end
