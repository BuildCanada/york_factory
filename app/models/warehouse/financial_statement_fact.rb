class Warehouse::FinancialStatementFact < Warehouse::Record
  CONCEPTS = %w[
    total_financial_assets total_liabilities net_financial_assets
    total_non_financial_assets accumulated_surplus opening_accumulated_surplus
    total_revenue total_expenses annual_surplus
  ].freeze
  STATEMENTS = %w[financial_position operations accumulated_surplus].freeze
  SCALES = [ 1, 1_000, 1_000_000 ].freeze

  belongs_to :financial_statement_extraction,
    class_name: "Warehouse::FinancialStatementExtraction",
    inverse_of: :financial_statement_facts

  validates :concept, inclusion: { in: CONCEPTS },
    uniqueness: { scope: :financial_statement_extraction_id }
  validates :statement, inclusion: { in: STATEMENTS }
  validates :scale, inclusion: { in: SCALES }
  validates :value, :raw_text, :raw_label, :source_page, :column_year, presence: true
  validates :source_page, numericality: { only_integer: true, greater_than: 0 }
  validates :extraction_confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
end
