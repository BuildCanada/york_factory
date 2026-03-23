class CreateRawIngestions < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_ingestions do |t|
      t.references :source, null: false, foreign_key: true
      t.datetime :fetched_at, null: false
      t.string :raw_file_path, null: false
      t.string :checksum, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end

    add_index :raw_ingestions, [:source_id, :checksum], unique: true
  end
end
