class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :format, null: false
      t.string :fetch_frequency
      t.datetime :last_fetched_at

      t.timestamps
    end

    add_index :sources, :name, unique: true
  end
end
