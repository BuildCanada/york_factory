class CreateLobbyists < ActiveRecord::Migration[8.1]
  def change
    create_table :lobbyists do |t|
      t.string :name, null: false
      t.string :registration_number
      t.string :lobbyist_type

      t.timestamps
    end

    add_index :lobbyists, :registration_number, unique: true, where: "registration_number IS NOT NULL"
  end
end
