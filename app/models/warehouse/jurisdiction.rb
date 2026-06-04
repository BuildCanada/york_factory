class Warehouse::Jurisdiction < Warehouse::Record
  enum :level, {
    municipal: "municipal",
    regional: "regional",
    provincial: "provincial",
    territorial: "territorial",
    federal: "federal",
    crown_corp: "crown_corp",
    authority: "authority"
  }

  has_many :organizations, dependent: :restrict_with_error
  has_many :kpi_documents, dependent: :restrict_with_error

  validates :name, :code, :level, :slug, presence: true
  validates :code, uniqueness: true
  validates :slug, uniqueness: true
  validates :fiscal_year_start_month, presence: true, inclusion: { in: 1..12 }
  validates :default_currency, presence: true
end
