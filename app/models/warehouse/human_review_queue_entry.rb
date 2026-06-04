class Warehouse::HumanReviewQueueEntry < Warehouse::Record
  self.table_name = "warehouse.human_review_queue"
  self.primary_key = :extracted_observation_id

  belongs_to :extracted_observation,
    class_name: "Warehouse::ExtractedObservation",
    foreign_key: :extracted_observation_id
  belongs_to :measure
  belongs_to :document, class_name: "Warehouse::KpiDocument"

  scope :by_severity, -> {
    order(Arel.sql("highest_open_severity_rank DESC NULLS LAST, created_at ASC"))
  }

  def readonly?
    true
  end
end
