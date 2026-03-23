class FiscalAuthority < ApplicationRecord
  belongs_to :government_entity
  belongs_to :raw_ingestion, optional: true
  belongs_to :lineage_entry, optional: true

  enum :document_type, {
    main: "main",
    supp_a: "supp_a",
    supp_b: "supp_b",
    supp_c: "supp_c"
  }

  enum :vote_type, {
    operating: "operating",
    capital: "capital",
    grants_contributions: "grants_contributions",
    statutory: "statutory"
  }

  validates :fiscal_year, presence: true
  validates :document_type, presence: true
  validates :vote_type, presence: true
end
