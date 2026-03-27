class CreateFiscalAuthorities < ActiveRecord::Migration[8.1]
  def change
    create_table :fiscal_authorities do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :fiscal_year, null: false
      t.string :document_type, null: false
      t.string :vote_number
      t.string :vote_type, null: false
      t.text :description
      t.decimal :amount, precision: 15, scale: 2
      t.references :raw_ingestion, foreign_key: true
      t.references :lineage_entry, foreign_key: { to_table: :lineage_entries }

      t.timestamps
    end

    add_index :fiscal_authorities,
      [ :organization_id, :fiscal_year, :document_type, :vote_number ],
      unique: true,
      name: "idx_fiscal_authorities_unique"
  end
end
