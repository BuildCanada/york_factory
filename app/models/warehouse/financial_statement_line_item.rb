class Warehouse::FinancialStatementLineItem < Warehouse::Record
  FLOWS = %w[revenue expense].freeze
  SCALES = Warehouse::FinancialStatementFact::SCALES

  belongs_to :financial_statement_extraction,
    class_name: "Warehouse::FinancialStatementExtraction",
    inverse_of: :financial_statement_line_items

  validates :flow, inclusion: { in: FLOWS }
  validates :category, :label, :raw_text, :column_year, presence: true
  validates :scale, inclusion: { in: SCALES }
  validates :source_page, numericality: { only_integer: true, greater_than: 0 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: [ :financial_statement_extraction_id, :flow ] }
  validates :extraction_confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
end
