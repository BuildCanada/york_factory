class Warehouse::FinancialStatementExtraction < Warehouse::Record
  STATUSES = %w[pending extracting extracted needs_review approved rejected failed].freeze
  STATEMENT_BASES = %w[consolidated non_consolidated].freeze
  LANGUAGES = %w[en fr bilingual].freeze

  has_many :financial_statement_facts,
    class_name: "Warehouse::FinancialStatementFact",
    dependent: :restrict_with_error,
    inverse_of: :financial_statement_extraction

  has_object :extractor

  validates :institution_canonical_id, :document_canonical_id, :asset_sha256,
    :fiscal_year_end, :extractor_version, :status, presence: true
  validates :asset_sha256, format: { with: /\A[0-9a-f]{64}\z/ },
    uniqueness: { scope: :extractor_version }
  validates :status, inclusion: { in: STATUSES }
  validates :statement_basis, inclusion: { in: STATEMENT_BASES }
  validates :language, inclusion: { in: LANGUAGES }, allow_nil: true
  validate :review_fields_are_paired

  scope :approved, -> { where(status: "approved") }
  scope :for_institution, ->(canonical_id) { where(institution_canonical_id: canonical_id) }

  def approve!(reviewer:, notes: nil)
    raise ActiveRecord::RecordInvalid, self if reviewed_at.present?
    raise ArgumentError, "only extracted or needs-review results can be approved" unless status.in?(%w[extracted needs_review])

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
end
