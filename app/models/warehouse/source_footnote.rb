class Warehouse::SourceFootnote < Warehouse::Record
  self.table_name = "warehouse.source_footnotes"

  belongs_to :document, class_name: "Warehouse::KpiDocument"
  belongs_to :agent_run, optional: true

  has_many :observation_footnotes,
    class_name: "Warehouse::ObservationFootnote",
    foreign_key: :source_footnote_id,
    dependent: :delete_all
  has_many :extracted_observations,
    through: :observation_footnotes

  validates :footnote_text, presence: true
end
