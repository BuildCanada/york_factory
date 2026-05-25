class Warehouse::OrganizationLineage < Warehouse::Record
  TRANSITION_KINDS = %w[rename merge split absorb spin_off revived].freeze

  belongs_to :predecessor, class_name: "Warehouse::Organization"
  belongs_to :successor, class_name: "Warehouse::Organization"
  belongs_to :acknowledged_in_document,
    class_name: "Warehouse::KpiDocument",
    foreign_key: :acknowledged_in_document_id,
    optional: true

  validates :transition_year, presence: true
  validates :transition_kind, presence: true, inclusion: { in: TRANSITION_KINDS }
  validate :predecessor_and_successor_distinct

  validates :predecessor_id, uniqueness: {
    scope: [ :successor_id, :transition_year, :transition_kind ]
  }

  private

  def predecessor_and_successor_distinct
    return unless predecessor_id.present? && predecessor_id == successor_id

    errors.add(:successor_id, "must differ from predecessor")
  end
end
