class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :canonical_name, null: false
      t.integer :org_id_infobase

      t.timestamps
    end

    add_index :organizations, :canonical_name, unique: true
    add_index :organizations, :org_id_infobase, unique: true, where: "org_id_infobase IS NOT NULL"
  end
end
