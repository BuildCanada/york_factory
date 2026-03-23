class LineageEntry < ApplicationRecord
  belongs_to :raw_ingestion, optional: true

  enum :transformation_type, {
    exact_match: "exact_match",
    case_insensitive: "case_insensitive",
    encoding_normalized: "encoding_normalized",
    llm_fuzzy: "llm_fuzzy",
    skipped: "skipped",
    deterministic: "deterministic"
  }

  validates :transformation_type, presence: true
end
