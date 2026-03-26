class CreateFeedItems < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_items do |t|
      t.string :item_type, null: false
      t.jsonb :title_translations, default: {}
      t.jsonb :subtitle_translations, default: {}
      t.string :author
      t.jsonb :body_translations, default: {}
      t.string :url
      t.text :embed_code
      t.string :source_url, null: false
      t.string :tags, array: true, default: []
      t.boolean :featured, default: false

      t.timestamps
    end
    add_index :feed_items, :source_url, unique: true
    add_index :feed_items, :item_type
    add_index :feed_items, :featured
    add_index :feed_items, :tags, using: :gin
  end
end
