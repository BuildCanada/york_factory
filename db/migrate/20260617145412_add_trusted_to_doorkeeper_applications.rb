class AddTrustedToDoorkeeperApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_applications, :trusted, :boolean, default: false, null: false
  end
end
