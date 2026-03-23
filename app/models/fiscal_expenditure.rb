class FiscalExpenditure < ApplicationRecord
  belongs_to :organization
  belongs_to :raw_ingestion, optional: true
  belongs_to :lineage_entry, optional: true

  enum :vote_type, {
    operating: "operating",
    capital: "capital",
    grants_contributions: "grants_contributions",
    statutory: "statutory"
  }

  validates :fiscal_year, presence: true
  validates :vote_type, presence: true
end
