class Warehouse::ObservationReviewFlag < Warehouse::Record
  SEVERITIES = %w[low medium high critical].freeze
  SEVERITY_RANK = { "low" => 1, "medium" => 2, "high" => 3, "critical" => 4 }.freeze

  self.table_name = "warehouse.observation_review_flags"

  belongs_to :extracted_observation, class_name: "Warehouse::ExtractedObservation"

  validates :flag_type, :message, presence: true
  validates :severity, inclusion: { in: SEVERITIES }
  validate  :resolved_pair_consistent

  scope :open,     -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  def open?
    resolved_at.nil?
  end

  def resolve!(resolved_by:, notes: nil)
    update!(resolved_at: Time.current, resolved_by: resolved_by, resolution_notes: notes)
  end

  private

  def resolved_pair_consistent
    return if resolved_at.nil? == resolved_by.nil?
    errors.add(:resolved_at, "and resolved_by must be set together")
  end
end
