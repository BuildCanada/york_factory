class Warehouse::InstitutionRelationship < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  RELATIONSHIP_TYPES = %w[
    administrative_parent reports_to owned_by controlled_by consolidated_into
    governed_by operated_by member_of succeeds
  ].freeze
  OWNERSHIP_BASES = %w[equity voting statutory board_appointment accounting_control other].freeze

  belongs_to :source_institution,
    class_name: "Warehouse::Institution",
    inverse_of: :outgoing_relationships
  belongs_to :target_institution,
    class_name: "Warehouse::Institution",
    inverse_of: :incoming_relationships
  belongs_to :institution_source, class_name: "Warehouse::InstitutionSource", optional: true

  validates :relationship_type, inclusion: { in: RELATIONSHIP_TYPES }
  validates :ownership_percentage,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
    allow_nil: true
  validates :ownership_basis, inclusion: { in: OWNERSHIP_BASES }, allow_nil: true
  validates :source_institution_id,
    uniqueness: {
      scope: :institution_release_id,
      conditions: -> { where(primary: true) }
    },
    if: :primary?
  validate :institutions_are_distinct
  validate :valid_date_range
  validate :primary_edge_is_hierarchical

  private

  def institutions_are_distinct
    return if source_institution_id.nil? || source_institution_id != target_institution_id

    errors.add(:target_institution, "must differ from source institution")
  end

  def valid_date_range
    return if valid_from.nil? || valid_to.nil? || valid_to >= valid_from

    errors.add(:valid_to, "must be on or after valid_from")
  end

  def primary_edge_is_hierarchical
    return unless primary? && relationship_type != "administrative_parent"

    errors.add(:primary, "is only valid for administrative_parent relationships")
  end
end
