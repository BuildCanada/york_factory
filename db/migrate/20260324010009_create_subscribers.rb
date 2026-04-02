class CreateSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :subscribers do |t|
      t.string :first_name
      t.string :last_name
      t.string :email, null: false
      t.string :postal_code

      t.timestamps
    end
    add_index :subscribers, :email, unique: true
  end
end
