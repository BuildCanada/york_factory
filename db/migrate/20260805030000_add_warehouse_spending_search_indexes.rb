class AddWarehouseSpendingSearchIndexes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE INDEX idx_spending_awards_search_document
      ON warehouse.spending_awards USING gin (
        to_tsvector(
          'simple',
          coalesce(recipient_name, '') || ' ' ||
          coalesce(program_name, '') || ' ' ||
          coalesce(description, '') || ' ' ||
          coalesce(title, '')
        )
      )
    SQL
    add_index "warehouse.spending_awards", [ :state, :payer_name ], name: "idx_spending_awards_state_payer"
    add_index "warehouse.spending_awards", [ :state, :program_name ], name: "idx_spending_awards_state_program"
    add_index "warehouse.spending_awards", [ :state, :province_code ], name: "idx_spending_awards_state_province"
    add_index "warehouse.spending_awards", [ :state, :country_code ], name: "idx_spending_awards_state_country"
  end

  def down
    remove_index "warehouse.spending_awards", name: "idx_spending_awards_state_country"
    remove_index "warehouse.spending_awards", name: "idx_spending_awards_state_province"
    remove_index "warehouse.spending_awards", name: "idx_spending_awards_state_program"
    remove_index "warehouse.spending_awards", name: "idx_spending_awards_state_payer"
    execute "DROP INDEX warehouse.idx_spending_awards_search_document"
  end
end
