class Warehouse::MetricVersion < Warehouse::Record
  self.table_name = "warehouse.metric_versions"

  belongs_to :measure
  belongs_to :source,   optional: true
  belongs_to :document, class_name: "Warehouse::KpiDocument", optional: true

  has_many :extracted_observations,
    class_name: "Warehouse::ExtractedObservation",
    foreign_key: :metric_version_id,
    dependent: :nullify
  has_many :canonical_observations,
    class_name: "Warehouse::CanonicalObservation",
    foreign_key: :metric_version_id,
    dependent: :nullify

  validates :version_label, :definition, presence: true
  validates :version_label, uniqueness: { scope: :measure_id }
  validate :active_range_valid

  scope :active_on, ->(date) {
    where("(active_from IS NULL OR active_from <= ?) AND (active_to IS NULL OR active_to >= ?)", date, date)
  }

  private

  def active_range_valid
    return if active_to.blank? || active_from.blank?
    errors.add(:active_to, "must be on or after active_from") if active_to < active_from
  end
end
