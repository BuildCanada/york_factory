class AddCanonicalVersionsToWarehouseSpendingAwards < ActiveRecord::Migration[8.1]
  def up
    add_column "warehouse.spending_awards", :canonical_key, :string
    add_column "warehouse.spending_awards", :is_canonical, :boolean, null: false, default: true

    execute <<~SQL
      UPDATE warehouse.spending_awards
      SET canonical_key = external_key
    SQL
    change_column_null "warehouse.spending_awards", :canonical_key, false

    add_index "warehouse.spending_awards", [ :source_id, :canonical_key ],
      name: "idx_spending_awards_canonical_key"
    add_index "warehouse.spending_awards", [ :source_id, :is_canonical, :state ],
      name: "idx_spending_awards_searchable"
  end

  def down
    remove_index "warehouse.spending_awards", name: "idx_spending_awards_searchable"
    remove_index "warehouse.spending_awards", name: "idx_spending_awards_canonical_key"
    remove_column "warehouse.spending_awards", :is_canonical
    remove_column "warehouse.spending_awards", :canonical_key
  end
end
