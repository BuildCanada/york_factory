class LineageEntry < ApplicationRecord
  belongs_to :raw_ingestion, optional: true

  enum :transformation_type, {
    exact_match: "exact_match",
    case_insensitive: "case_insensitive",
    encoding_normalized: "encoding_normalized",
    llm_fuzzy: "llm_fuzzy",
    skipped: "skipped",
    deterministic: "deterministic",
    auto_created_for_review: "auto_created_for_review",
    corporate_cross_ref: "corporate_cross_ref"
  }

  validates :transformation_type, presence: true
end
