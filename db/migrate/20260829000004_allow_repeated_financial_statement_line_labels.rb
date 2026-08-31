class AllowRepeatedFinancialStatementLineLabels < ActiveRecord::Migration[8.1]
  def change
    remove_index "warehouse.financial_statement_line_items",
      name: "index_financial_statement_line_items_identity"
    remove_index "warehouse.financial_statement_line_items",
      name: "index_financial_statement_line_items_order"
    add_index "warehouse.financial_statement_line_items",
      [ :financial_statement_extraction_id, :flow, :position ], unique: true,
      name: "index_financial_statement_line_items_order"
  end
end
