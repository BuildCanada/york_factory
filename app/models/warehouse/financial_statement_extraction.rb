class Warehouse::FinancialStatementExtraction < Warehouse::Record
  STATUSES = %w[pending extracting extracted needs_review approved rejected failed].freeze
  STATEMENT_BASES = %w[consolidated non_consolidated].freeze
  LANGUAGES = %w[en fr bilingual].freeze

  belongs_to :institution_release, class_name: "Warehouse::InstitutionRelease"

  has_many :financial_statement_facts,
    class_name: "Warehouse::FinancialStatementFact",
    dependent: :restrict_with_error,
    inverse_of: :financial_statement_extraction

  has_many :financial_statement_line_items,
    -> { order(:flow, :position) },
    class_name: "Warehouse::FinancialStatementLineItem",
    dependent: :restrict_with_error,
    inverse_of: :financial_statement_extraction

  has_object :extractor

  validates :institution_canonical_id, :document_canonical_id, :asset_sha256,
    :fiscal_year_end, :extractor_version, :status, presence: true
  validates :asset_sha256, format: { with: /\A[0-9a-f]{64}\z/ },
    uniqueness: { scope: [ :institution_release_id, :extractor_version, :fiscal_year_end ] }
  validates :status, inclusion: { in: STATUSES }
  validates :statement_basis, inclusion: { in: STATEMENT_BASES }
  validates :language, inclusion: { in: LANGUAGES }, allow_nil: true
  validate :review_fields_are_paired
  validate :completed_extractions_have_check_results
  validate :approved_extractions_have_review_provenance
  validate :source_asset_belongs_to_release
  validate :document_year_matches_fiscal_year

  scope :approved, -> { where(status: "approved") }
  scope :publishable_details, -> do
    approved.where(extractor_version: Warehouse::FinancialStatementExtraction::DetailedPipeline::EXTRACTOR_VERSION)
  end
  scope :for_institution, ->(canonical_id) { where(institution_canonical_id: canonical_id) }

  def self.verification_checks(check_results)
    Array(check_results).map do |check|
      check = check.stringify_keys
      { id: check["id"], status: check["status"], detail: check["detail"] }
    end
  end

  def approve!(reviewer:, notes: nil)
    raise ActiveRecord::RecordInvalid, self if reviewed_at.present?
    raise ArgumentError, "only extracted or needs-review results can be approved" unless status.in?(%w[extracted needs_review])
    raise ArgumentError, "verification check results must be saved before approval" if check_results.blank?

    update!(status: "approved", reviewed_by: reviewer, reviewed_at: Time.current, review_notes: notes)
  end

  def reject!(reviewer:, notes: nil)
    raise ActiveRecord::RecordInvalid, self if reviewed_at.present?
    raise ArgumentError, "a pending extraction cannot be rejected" if status == "pending"

    update!(status: "rejected", reviewed_by: reviewer, reviewed_at: Time.current, review_notes: notes)
  end

  private

  def review_fields_are_paired
    return if reviewed_at.nil? == reviewed_by.nil?

    errors.add(:reviewed_by, "must be present exactly when reviewed_at is present")
  end

  def completed_extractions_have_check_results
    return unless status.in?(%w[extracted needs_review approved rejected failed]) && check_results.blank?

    errors.add(:check_results, "must be saved for a completed extraction")
  end

  def approved_extractions_have_review_provenance
    return unless status == "approved" && (reviewed_at.blank? || reviewed_by.blank?)

    errors.add(:reviewed_at, "and reviewer must be saved before approval")
  end

  def source_asset_belongs_to_release
    return unless institution_release && document_canonical_id.present? && asset_sha256.present?

    document = institution_release.institution_documents.find_by(canonical_id: document_canonical_id)
    if document && institution_canonical_id.present? && document.institution.canonical_id != institution_canonical_id
      errors.add(:institution_canonical_id, "must identify the release document's reporting institution")
    end
    unless document&.institution_document_assets&.exists?(content_sha256: asset_sha256)
      errors.add(:asset_sha256, "must identify an archived asset on the release document")
    end
  end

  def document_year_matches_fiscal_year
    return if document_canonical_id.blank? || fiscal_year_end.blank?

    match = document_canonical_id.match(%r{/documents/(?:financial-statements|annual-report)/(\d{4})/})
    return unless match
    return if match[1].to_i == fiscal_year_end.year

    errors.add(:fiscal_year_end, "year must match the source document canonical ID")
  end
end
