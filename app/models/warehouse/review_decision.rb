class Warehouse::ReviewDecision < Warehouse::Record
  DECISIONS = %w[approved rejected edited needs_more_info].freeze

  self.table_name = "warehouse.review_decisions"

  belongs_to :extracted_observation, class_name: "Warehouse::ExtractedObservation"

  validates :reviewer, presence: true
  validates :decision, presence: true, inclusion: { in: DECISIONS }
end
