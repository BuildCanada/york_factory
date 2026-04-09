class ReplaceAdminWithRolesAndAddressFields < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :string, default: "member", null: false
    add_column :users, :postal_code, :string
    add_column :users, :address_line1, :string
    add_column :users, :address_line2, :string
    add_column :users, :city, :string
    add_column :users, :province, :string

    reversible do |dir|
      dir.up do
        execute "UPDATE users SET role = 'admin' WHERE admin = true"
      end
      dir.down do
        execute "UPDATE users SET admin = true WHERE role = 'admin'"
      end
    end

    remove_column :users, :admin, :boolean, default: false
  end
end
