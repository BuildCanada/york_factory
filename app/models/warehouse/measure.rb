class Warehouse::Measure < Warehouse::Record
  belongs_to :organization, optional: true
  belongs_to :unit
  belongs_to :agent_run, optional: true
  has_many :citations,
    class_name: "Warehouse::MeasureCitation",
    foreign_key: :measure_id,
    inverse_of: :measure,
    dependent: :destroy
  has_many :facts,
    class_name: "Warehouse::MeasureFact",
    foreign_key: :measure_id,
    inverse_of: :measure
  has_many :predecessor_lineages,
    class_name: "Warehouse::MeasureLineage",
    foreign_key: :successor_id,
    inverse_of: :successor,
    dependent: :destroy
  has_many :successor_lineages,
    class_name: "Warehouse::MeasureLineage",
    foreign_key: :predecessor_id,
    inverse_of: :predecessor,
    dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: :organization_id }
  validates :canonical_name, presence: true

  before_validation :normalize_service_category

  # Strip trailing parenthetical quality-attribute tags from a service_category
  # string. Toronto budget docs append year-specific framing tags like
  # "(Reliable, Resilient)", "(Accessible, Vibrant)" — these create UI
  # fragmentation when each year picks a different combination. The clean
  # form ("Road and Sidewalk Management") is the canonical grouping key.
  def self.normalize_service_category(raw)
    return raw if raw.blank?
    raw.to_s.sub(/\s*\([^()]*\)\s*\z/, "").strip.presence
  end

  private

  def normalize_service_category
    self.service_category = self.class.normalize_service_category(service_category)
  end
end
