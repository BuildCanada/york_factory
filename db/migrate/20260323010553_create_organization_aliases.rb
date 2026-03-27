class CreateOrganizationAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_aliases do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :alias_name, null: false
      t.date :valid_from
      t.date :valid_to

      t.timestamps
    end

    add_index :organization_aliases, [ :alias_name, :valid_from ], unique: true
  end
end
