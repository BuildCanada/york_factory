class CreateCorporateDirectors < ActiveRecord::Migration[8.1]
  def change
    create_table :corporate_directors do |t|
      t.string :full_name, null: false
      t.string :normalized_name, null: false
      t.string :address
      t.string :province
      t.string :postal_code
      t.string :country
      t.boolean :is_resident_canadian
      t.timestamps
    end

    add_index :corporate_directors, :normalized_name
    add_index :corporate_directors, [:normalized_name, :postal_code], name: "idx_directors_name_postal"
  end
end
