require "ruby_llm/schema"

class Warehouse::FinancialStatementExtraction::ResponseSchema < RubyLLM::Schema
  string :language, enum: %w[en fr bilingual]
  string :statement_basis, enum: %w[consolidated non_consolidated]
  integer :fiscal_year
  boolean :remeasurement_present
  boolean :operations_adjustment_present
  boolean :rollforward_adjustment_present
  boolean :total_financial_assets_single_component
  boolean :total_liabilities_single_component
  boolean :total_non_financial_assets_single_component
  array :facts, min_items: 1, max_items: 9 do
    object do
      string :concept, enum: Warehouse::FinancialStatementFact::CONCEPTS
      string :statement, enum: Warehouse::FinancialStatementFact::STATEMENTS
      string :raw_label
      string :raw_text
      integer :scale
      integer :excerpt_page, minimum: 1
      string :column_year
      number :confidence, minimum: 0, maximum: 1
    end
  end
end
