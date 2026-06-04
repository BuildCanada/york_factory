class Warehouse::Alert < Warehouse::Record
  CONDITION_TYPES = %w[
    above below percent_change absolute_change missing_update
    rank_change new_definition new_component conflicting_source
  ].freeze
  SEVERITIES = %w[low medium high critical].freeze

  self.table_name = "warehouse.alerts"

  belongs_to :measure, optional: true
  belongs_to :geo_boundary, optional: true
  belongs_to :jurisdiction, optional: true
  belongs_to :observed_organization, class_name: "Warehouse::Organization", optional: true

  has_many :events,
    class_name: "Warehouse::AlertEvent",
    foreign_key: :alert_id,
    dependent: :destroy

  validates :name, presence: true
  validates :condition_type, inclusion: { in: CONDITION_TYPES }
  validates :severity, inclusion: { in: SEVERITIES }

  scope :enabled, -> { where(enabled: true) }

  def evaluate!
    Warehouse::Alert::Evaluator.new(self).evaluate!
  end
end
