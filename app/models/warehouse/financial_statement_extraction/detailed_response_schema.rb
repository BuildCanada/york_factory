require "ruby_llm/schema"

class Warehouse::FinancialStatementExtraction::DetailedResponseSchema < RubyLLM::Schema
  integer :fiscal_year
  array :line_items, min_items: 1 do
    object do
      string :flow, enum: Warehouse::FinancialStatementLineItem::FLOWS
      string :category
      string :label
      string :raw_text
      integer :scale
      integer :excerpt_page, minimum: 1
      string :column_year
      number :confidence, minimum: 0, maximum: 1
    end
  end
end
