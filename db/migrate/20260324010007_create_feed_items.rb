class CreateFeedItems < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_items do |t|
      t.string :item_type, null: false
      t.string :title_en
      t.string :title_fr
      t.string :subtitle_en
      t.string :subtitle_fr
      t.string :author
      t.string :url
      t.text :embed_code
      t.string :source_url, null: false
      t.string :tags, array: true, default: []
      t.boolean :featured, default: false
      t.datetime :published_at

      t.timestamps
    end
    add_index :feed_items, :source_url, unique: true
    add_index :feed_items, :item_type
    add_index :feed_items, :featured
    add_index :feed_items, :tags, using: :gin
  end
end
