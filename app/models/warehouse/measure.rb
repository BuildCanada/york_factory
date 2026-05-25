class Warehouse::Measure < Warehouse::Record
  belongs_to :organization, optional: true
  belongs_to :unit
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
end
