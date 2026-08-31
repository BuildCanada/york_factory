class Warehouse::Institution < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  CANONICAL_ID_FORMAT = /\Aca\/[a-z0-9]+(?:-[a-z0-9]+)*(?:\/[a-z0-9]+(?:-[a-z0-9]+)*)*\z/
  INSTITUTION_TYPES = %w[
    government department ministry agency authority board commission
    crown_corporation government_business_enterprise police_service fire_service
    public_library health_authority education_authority corporation other
  ].freeze
  GOVERNMENT_LEVELS = %w[
    federal provincial territorial regional municipal first_nation inuit metis joint other
  ].freeze
  STATUSES = %w[active inactive dissolved proposed unknown].freeze

  belongs_to :institution_source, class_name: "Warehouse::InstitutionSource", optional: true

  has_many :institution_identifiers, dependent: :restrict_with_error
  has_many :outgoing_relationships,
    class_name: "Warehouse::InstitutionRelationship",
    foreign_key: :source_institution_id,
    dependent: :restrict_with_error,
    inverse_of: :source_institution
  has_many :incoming_relationships,
    class_name: "Warehouse::InstitutionRelationship",
    foreign_key: :target_institution_id,
    dependent: :restrict_with_error,
    inverse_of: :target_institution
  has_many :institution_geographies, dependent: :restrict_with_error
  has_many :institution_documents, dependent: :restrict_with_error

  validates :canonical_id,
    presence: true,
    uniqueness: { scope: :institution_release_id },
    format: { with: CANONICAL_ID_FORMAT }
  validates :institution_type, inclusion: { in: INSTITUTION_TYPES }
  validates :government_level, inclusion: { in: GOVERNMENT_LEVELS }
  validates :status, inclusion: { in: STATUSES }
  validates :fiscal_year_start_month, inclusion: { in: 1..12 }, allow_nil: true
  validates :default_currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
  validates :website_url, format: { with: /\Ahttps?:\/\/[^\s]+\z/ }, allow_nil: true
  validate :canonical_id_uses_institution_namespace
  validate :has_upstream_name
  validate :active_date_range

  def active_at?(date = institution_release.effective_on)
    status == "active" &&
      (active_from.nil? || active_from <= date) &&
      (active_to.nil? || active_to >= date)
  end

  private

  def canonical_id_uses_institution_namespace
    return if canonical_id.blank?
    return unless canonical_id.start_with?("ca/sources/", "ca/geography/") || canonical_id.include?("/documents/")

    errors.add(:canonical_id, "uses a reserved namespace")
  end

  def has_upstream_name
    errors.add(:base, "an English or French upstream name is required") if name_en.blank? && name_fr.blank?
  end

  def active_date_range
    return if active_from.nil? || active_to.nil? || active_to >= active_from

    errors.add(:active_to, "must be on or after active_from")
  end
end
