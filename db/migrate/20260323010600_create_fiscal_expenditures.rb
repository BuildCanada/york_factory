class CreateFiscalExpenditures < ActiveRecord::Migration[8.1]
  def change
    create_table :fiscal_expenditures do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :fiscal_year, null: false
      t.string :vote_number
      t.string :vote_type, null: false
      t.text :description
      t.decimal :pa_voted_ceiling, precision: 15, scale: 2
      t.decimal :actual_expenditure, precision: 15, scale: 2
      t.references :raw_ingestion, foreign_key: true
      t.references :lineage_entry, foreign_key: { to_table: :lineage_entries }

      t.timestamps
    end

    add_index :fiscal_expenditures,
      [:organization_id, :fiscal_year, :vote_number],
      unique: true,
      name: "idx_fiscal_expenditures_unique"
  end
end
