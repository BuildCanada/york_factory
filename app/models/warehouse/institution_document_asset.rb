class Warehouse::InstitutionDocumentAsset < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  ASSET_ROLES = %w[final draft amended part container unknown].freeze
  RIGHTS_STATUSES = %w[redistributable metadata_only restricted unknown].freeze

  belongs_to :institution_document, class_name: "Warehouse::InstitutionDocument"

  validates :content_sha256,
    presence: true,
    uniqueness: { scope: [ :institution_release_id, :institution_document_id ] },
    format: { with: /\A[0-9a-f]{64}\z/ }
  validates :asset_role, inclusion: { in: ASSET_ROLES }
  validates :rights_status, inclusion: { in: RIGHTS_STATUSES }
  validates :download_url, :retrieved_at, :archive_path, :mime_type, :byte_size, presence: true
  validates :download_url, format: { with: /\Ahttps?:\/\/[^\s]+\z/ }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :part_index, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :part_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :preferred,
    uniqueness: { scope: [ :institution_release_id, :institution_document_id ] },
    if: :preferred?
  validates :archive_path, format: { with: /\Asha256\/[a-z0-9._\/-]+\z/ }
  validate :part_fields_match_role
  validate :archive_path_has_no_parent_segments

  private

  def part_fields_match_role
    if asset_role == "part"
      errors.add(:part_index, "is required for part assets") if part_index.blank?
      errors.add(:part_count, "must be at least the part index") if part_count.present? && part_index.present? && part_count < part_index
    elsif part_index.present? || part_count.present?
      errors.add(:part_index, "is only valid for part assets")
    end
  end

  def archive_path_has_no_parent_segments
    return if archive_path.blank? || archive_path.split("/").exclude?("..")

    errors.add(:archive_path, "must be bundle-relative")
  end
end
