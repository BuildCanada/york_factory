class Warehouse::ExtractedObservation < Warehouse::Record
  VALUE_TYPES     = %w[actual target projected plan budget].freeze
  # ytd_q* quarters are relative to the observation's own reporting calendar
  # (the jurisdiction's fiscal year, per jurisdictions.fiscal_year_start_month)
  # — they don't imply the same calendar months across jurisdictions. Economy
  # importers only write full_year and month.
  PERIOD_BASES    = %w[full_year ytd_q1 ytd_q2 ytd_q3 as_of_date month quarter].freeze
  REVIEW_STATUSES = %w[pending approved rejected superseded].freeze

  self.table_name = "warehouse.extracted_observations"

  belongs_to :measure
  belongs_to :metric_version, class_name: "Warehouse::MetricVersion", optional: true
  belongs_to :composition,    class_name: "Warehouse::MetricComposition", optional: true
  belongs_to :component,      class_name: "Warehouse::MetricComponent",   optional: true
  belongs_to :document, class_name: "Warehouse::KpiDocument"
  belongs_to :agent_run, optional: true

  belongs_to :reporting_organization,
    class_name: "Warehouse::Organization", optional: true
  belongs_to :responsible_organization,
    class_name: "Warehouse::Organization", optional: true
  belongs_to :observed_organization,
    class_name: "Warehouse::Organization", optional: true

  belongs_to :geo_boundary, optional: true
  belongs_to :jurisdiction, optional: true

  has_one :canonical_observation,
    class_name: "Warehouse::CanonicalObservation",
    foreign_key: :extracted_observation_id,
    dependent: :restrict_with_error

  has_many :review_flags,
    class_name: "Warehouse::ObservationReviewFlag",
    foreign_key: :extracted_observation_id,
    inverse_of: :extracted_observation,
    dependent: :destroy
  has_many :review_decisions,
    class_name: "Warehouse::ReviewDecision",
    foreign_key: :extracted_observation_id,
    inverse_of: :extracted_observation,
    dependent: :destroy
  has_many :extraction_assertions,
    class_name: "Warehouse::ExtractionAssertion",
    foreign_key: :extracted_observation_id,
    inverse_of: :extracted_observation,
    dependent: :destroy
  has_many :observation_footnotes,
    class_name: "Warehouse::ObservationFootnote",
    foreign_key: :extracted_observation_id,
    inverse_of: :extracted_observation,
    dependent: :delete_all
  has_many :source_footnotes,
    through: :observation_footnotes

  has_object :period_basis_classifier

  validates :measurement_year, presence: true
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }
  validates :period_basis, presence: true, inclusion: { in: PERIOD_BASES }
  validates :review_status, inclusion: { in: REVIEW_STATUSES }
  validates :extraction_confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
  validates :measure_id, uniqueness: {
    scope: [ :measurement_year, :value_type, :period_basis, :period_start, :document_id,
             :composition_id, :component_id, :observed_organization_id, :geo_boundary_id,
             :jurisdiction_id ]
  }

  scope :pending,      -> { where(review_status: "pending") }
  scope :approved,     -> { where(review_status: "approved") }
  scope :rejected,     -> { where(review_status: "rejected") }
  scope :for_review,   -> { where(needs_review: true) }

  def approved?
    review_status == "approved"
  end

  def open_review_flags
    review_flags.open
  end

  # Approve via the audited review path. Records a review_decision, resolves any
  # open review flags, promotes to a canonical_observation, and flips state.
  def approve!(reviewer:, notes: nil, new_value: nil, status: "reported",
                vintage_date: nil, is_total: false, is_residual: false)
    transaction do
      previous_attrs = attributes_snapshot
      assign_attributes(new_value) if new_value.is_a?(Hash) && new_value.any?
      save! if changed?
      promote_to_canonical!(approved_by: reviewer, status: status, vintage_date: vintage_date,
                            is_total: is_total, is_residual: is_residual)
      open_review_flags.each { |f| f.resolve!(resolved_by: reviewer, notes: "auto-resolved on approval") }
      review_decisions.create!(
        reviewer: reviewer,
        decision: (new_value.present? ? "edited" : "approved"),
        previous_value: previous_attrs,
        new_value: new_value.presence,
        notes: notes
      )
    end
  end

  def reject!(reviewer:, notes: nil)
    transaction do
      previous_attrs = attributes_snapshot
      update!(review_status: "rejected", needs_review: false)
      open_review_flags.each { |f| f.resolve!(resolved_by: reviewer, notes: "auto-resolved on rejection") }
      review_decisions.create!(
        reviewer: reviewer,
        decision: "rejected",
        previous_value: previous_attrs,
        notes: notes
      )
    end
  end

  # Promote a reviewed claim into a trusted canonical fact. Idempotent on
  # extracted_observation_id (the unique index on canonical_observations).
  def promote_to_canonical!(approved_by: nil, status: "reported", vintage_date: nil,
                             is_total: false, is_residual: false)
    transaction do
      update!(review_status: "approved", needs_review: false)
      Warehouse::CanonicalObservation.find_or_create_by!(extracted_observation_id: id) do |c|
        c.measure_id        = measure_id
        c.metric_version_id = metric_version_id
        c.composition_id    = composition_id
        c.component_id      = component_id
        c.document_id       = document_id
        c.measurement_year  = measurement_year
        c.value_type        = value_type
        c.period_basis      = period_basis
        c.period_start      = period_start
        c.period_end        = period_end
        c.period_type       = period_type
        c.value_numeric     = value_numeric
        c.value_text        = value_text
        c.unit_id           = measure&.unit_id
        c.reporting_organization_id   = reporting_organization_id
        c.responsible_organization_id = responsible_organization_id
        c.observed_organization_id    = observed_organization_id || measure&.organization_id
        c.geo_boundary_id   = geo_boundary_id
        c.jurisdiction_id   = jurisdiction_id || measure&.organization&.jurisdiction_id
        c.status            = status
        c.vintage_date      = vintage_date || document&.published_at
        c.is_total          = is_total
        c.is_residual       = is_residual
        c.approved_by       = approved_by
      end
    end
  end

  private

  def attributes_snapshot
    attributes.slice(
      "value_numeric", "value_text", "value_raw", "measurement_year",
      "value_type", "period_basis", "period_start", "period_end", "period_type",
      "reporting_organization_id", "responsible_organization_id", "observed_organization_id",
      "geo_boundary_id", "jurisdiction_id", "extraction_confidence", "review_status"
    )
  end
end
