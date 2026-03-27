class CreateStandardObjectExpenditures < ActiveRecord::Migration[8.1]
  def change
    create_table :standard_object_expenditures do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :fiscal_year, null: false
      t.string :standard_object, null: false
      t.decimal :amount, precision: 15, scale: 2
      t.references :raw_ingestion, foreign_key: true

      t.timestamps
    end

    add_index :standard_object_expenditures,
      [ :organization_id, :fiscal_year, :standard_object ],
      unique: true,
      name: "idx_std_obj_expenditures_unique"
  end
end
