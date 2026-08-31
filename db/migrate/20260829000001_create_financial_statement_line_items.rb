class CreateFinancialStatementLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table "warehouse.financial_statement_line_items" do |t|
      t.references :financial_statement_extraction, null: false,
        foreign_key: { to_table: "warehouse.financial_statement_extractions" },
        index: { name: "index_financial_statement_line_items_on_extraction_id" }
      t.string :flow, null: false
      t.string :category, null: false
      t.string :label, null: false
      t.decimal :value, precision: 24, scale: 2, null: false
      t.string :raw_text, null: false
      t.integer :scale, null: false, default: 1
      t.integer :source_page, null: false
      t.string :column_year, null: false
      t.integer :position, null: false
      t.decimal :extraction_confidence, precision: 5, scale: 4
      t.timestamps

      t.index [ :financial_statement_extraction_id, :flow, :category, :label ], unique: true,
        name: "index_financial_statement_line_items_identity"
      t.index [ :financial_statement_extraction_id, :flow, :position ],
        name: "index_financial_statement_line_items_order"
      t.check_constraint "flow IN ('revenue','expense')",
        name: "financial_statement_line_items_flow"
      t.check_constraint "scale IN (1,1000,1000000)",
        name: "financial_statement_line_items_scale"
      t.check_constraint "source_page > 0", name: "financial_statement_line_items_source_page"
      t.check_constraint "position >= 0", name: "financial_statement_line_items_position"
      t.check_constraint "extraction_confidence IS NULL OR (extraction_confidence >= 0 AND extraction_confidence <= 1)",
        name: "financial_statement_line_items_confidence"
    end
  end
end
