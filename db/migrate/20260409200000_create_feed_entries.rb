class CreateFeedEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_entries do |t|
      t.string :feedable_type, null: false
      t.bigint :feedable_id, null: false
      t.datetime :published_at, null: false
      t.boolean :featured, default: false
      t.string :tags, array: true, default: []

      t.timestamps
    end

    add_index :feed_entries, [ :feedable_type, :feedable_id ], unique: true
    add_index :feed_entries, :published_at, order: :desc
    add_index :feed_entries, :featured
    add_index :feed_entries, :tags, using: :gin
  end
end
