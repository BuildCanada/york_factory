class DropFeedItems < ActiveRecord::Migration[8.1]
  def up
    drop_table :feed_items
  end

  def down
    create_table :feed_items do |t|
      t.string :author
      t.text :embed_code
      t.boolean :featured, default: false
      t.string :item_type, null: false
      t.datetime :published_at
      t.string :source_url, null: false
      t.string :subtitle_en
      t.string :subtitle_fr
      t.string :tags, array: true, default: []
      t.string :title_en
      t.string :title_fr
      t.string :url

      t.timestamps
    end

    add_index :feed_items, :featured
    add_index :feed_items, :item_type
    add_index :feed_items, :source_url, unique: true
    add_index :feed_items, :tags, using: :gin
  end
end
