class Warehouse::MeasureCitation < Warehouse::Record
  VALUE_TYPES = %w[actual target projected plan budget].freeze
  PERIOD_BASES = %w[full_year ytd_q1 ytd_q2 ytd_q3 as_of_date].freeze

  belongs_to :measure
  belongs_to :document, class_name: "Warehouse::KpiDocument"

  validates :measurement_year, presence: true
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }
  validates :period_basis, presence: true, inclusion: { in: PERIOD_BASES }
  validates :measure_id, uniqueness: {
    scope: [ :measurement_year, :value_type, :period_basis, :document_id ]
  }
end
