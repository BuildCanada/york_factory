class CreateCorporateEntityAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :corporate_entity_aliases do |t|
      t.references :corporate_entity, null: false, foreign_key: true
      t.string :alias_name, null: false
      t.date :effective_date
      t.date :expiry_date
      t.timestamps
    end

    add_index :corporate_entity_aliases, :alias_name
    add_index :corporate_entity_aliases, [:corporate_entity_id, :alias_name], unique: true,
      name: "idx_corp_alias_entity_name"
  end
end
