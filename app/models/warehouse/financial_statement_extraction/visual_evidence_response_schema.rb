require "ruby_llm/schema"

class Warehouse::FinancialStatementExtraction::VisualEvidenceResponseSchema < RubyLLM::Schema
  array :claims, min_items: 1 do
    object do
      string :id
      boolean :found
      string :transcribed_label
      string :transcribed_category
      string :raw_text
      string :column_year
      integer :excerpt_page
    end
  end
end
