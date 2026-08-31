class Warehouse::InstitutionDocument < Warehouse::Record
  include Warehouse::InstitutionReleaseRecord

  DOCUMENT_TYPES = %w[
    annual-report financial-statements statement-of-financial-information
    financial-data-return auditor-report remuneration-report other
  ].freeze

  belongs_to :institution
  belongs_to :institution_source, class_name: "Warehouse::InstitutionSource"
  has_many :institution_document_assets, dependent: :restrict_with_error

  validates :canonical_id,
    presence: true,
    uniqueness: { scope: :institution_release_id },
    format: { with: Warehouse::Institution::CANONICAL_ID_FORMAT }
  validates :document_type, inclusion: { in: DOCUMENT_TYPES }
  validates :document_variant, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :source_page_url, :download_url,
    format: { with: /\Ahttps?:\/\/[^\s]+\z/ },
    allow_nil: true
  validate :canonical_id_belongs_to_reporting_institution
  validate :fiscal_date_range

  private

  def fiscal_date_range
    return if fiscal_period_start.nil? || fiscal_period_end.nil? || fiscal_period_end >= fiscal_period_start

    errors.add(:fiscal_period_end, "must be on or after fiscal_period_start")
  end

  def canonical_id_belongs_to_reporting_institution
    return if canonical_id.blank? || institution.nil?
    return if canonical_id.start_with?("#{institution.canonical_id}/documents/")

    errors.add(:canonical_id, "must be under the reporting institution's documents namespace")
  end
end
