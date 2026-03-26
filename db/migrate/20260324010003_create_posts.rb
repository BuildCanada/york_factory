class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :slug, null: false
      t.jsonb :title_translations, default: {}
      t.jsonb :summary_translations, default: {}
      t.jsonb :body_translations, default: {}
      t.boolean :hidden, default: false
      t.datetime :published_at

      t.timestamps
    end
    add_index :posts, :slug, unique: true
  end
end
