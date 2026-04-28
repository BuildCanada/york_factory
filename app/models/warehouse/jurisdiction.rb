class Warehouse::Jurisdiction < Warehouse::Record
  enum :level, { federal: "federal", provincial: "provincial", territorial: "territorial" }

  validates :name, :code, :level, presence: true
  validates :code, uniqueness: true
end
