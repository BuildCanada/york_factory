class Warehouse::MetricAlias < Warehouse::Record
  KINDS = %w[raw_text measure_equivalence].freeze

  self.table_name = "warehouse.metric_aliases"

  belongs_to :measure
  belongs_to :canonical_measure, class_name: "Warehouse::Measure", optional: true
  belongs_to :source,   optional: true
  belongs_to :document, class_name: "Warehouse::KpiDocument", optional: true

  validates :alias_text, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :equivalence_requires_canonical
  validate :equivalence_not_self

  scope :raw_text,               -> { where(kind: "raw_text") }
  scope :measure_equivalences,   -> { where(kind: "measure_equivalence") }

  def self.resolve_raw_text(text, measure_scope: nil)
    return nil if text.blank?
    scope = raw_text.where(alias_text: text)
    scope = scope.where(measure_id: measure_scope) if measure_scope
    scope.first&.measure
  end

  private

  def equivalence_requires_canonical
    return unless kind == "measure_equivalence"
    errors.add(:canonical_measure_id, "is required for measure_equivalence aliases") if canonical_measure_id.blank?
  end

  def equivalence_not_self
    return unless kind == "measure_equivalence"
    return if canonical_measure_id.blank?
    errors.add(:canonical_measure_id, "must differ from measure_id") if canonical_measure_id == measure_id
  end
end
