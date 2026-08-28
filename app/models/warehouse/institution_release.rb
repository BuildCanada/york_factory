require "set"

class Warehouse::InstitutionRelease < Warehouse::Record
  has_many :institution_sources, dependent: :restrict_with_error
  has_many :institutions, dependent: :restrict_with_error
  has_many :institution_identifiers, dependent: :restrict_with_error
  has_many :institution_relationships, dependent: :restrict_with_error
  has_many :institution_geography_snapshots, dependent: :restrict_with_error
  has_many :institution_geographies, dependent: :restrict_with_error
  has_many :institution_documents, dependent: :restrict_with_error
  has_many :institution_document_assets, dependent: :restrict_with_error
  has_many :institution_coverages, dependent: :restrict_with_error

  validates :version,
    presence: true,
    uniqueness: true,
    format: { with: /\A\d{4}-\d{2}-\d{2}\z/ }
  validates :effective_on, :schema_version, :published_at, :geography_vintage, :attribution, presence: true
  validate :version_matches_effective_on

  before_update :prevent_changes
  before_destroy :prevent_changes

  def published?
    persisted?
  end

  def validate_complete!
    errors.add(:base, "release must contain at least one institution") unless institutions.exists?

    mismatched_geography = institution_geography_snapshots.where.not(census_year: geography_vintage).exists?
    errors.add(:geography_vintage, "must match every included geography") if mismatched_geography

    errors.add(:base, "primary administrative-parent relationships contain a cycle") unless primary_parent_forest?
    validate_csd_authority_coverage! if institution_coverages.exists?(subject: "csd-inventory")

    raise ActiveRecord::RecordInvalid, self if errors.any?

    true
  end

  private

  def version_matches_effective_on
    return if version.blank? || effective_on.blank?
    return if version == effective_on.iso8601

    errors.add(:effective_on, "must match the dated release version")
  end

  def primary_parent_forest?
    parents = institution_relationships
      .where(primary: true, relationship_type: "administrative_parent")
      .pluck(:source_institution_id, :target_institution_id)
      .to_h

    parents.each_key do |start|
      seen = Set.new
      current = start
      while current
        return false if seen.include?(current)

        seen << current
        current = parents[current]
      end
    end

    true
  end

  def validate_csd_authority_coverage!
    csds = institution_geography_snapshots.where(boundary_type: "csd", census_year: geography_vintage)
    expected = geography_vintage == 2021 ? 5_161 : nil
    errors.add(:base, "unsupported complete CSD vintage #{geography_vintage}") unless expected
    errors.add(:base, "release must contain all #{expected} CSDs") if expected && csds.count != expected

    invalid_statuses = csds.where(authority_status: %w[legacy not_applicable]).count
    errors.add(:base, "#{invalid_statuses} CSDs lack an authority status") if invalid_statuses.positive?

    authority_snapshot_ids = institution_geographies.where(role: %w[governs administers])
      .select(:institution_geography_snapshot_id)
    resolved_without_link = csds.where(authority_status: %w[verified provisional])
      .where.not(id: authority_snapshot_ids).count
    if resolved_without_link.positive?
      errors.add(:base, "#{resolved_without_link} resolved CSDs lack an authority link")
    end
  end

  def prevent_changes
    errors.add(:base, "ontology releases are append-only")
    throw :abort
  end
end
