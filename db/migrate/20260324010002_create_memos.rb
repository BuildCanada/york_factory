class CreateMemos < ActiveRecord::Migration[8.1]
  def change
    create_table :memos do |t|
      t.string :slug, null: false
      t.jsonb :title_translations, default: {}
      t.jsonb :description_translations, default: {}
      t.references :author, foreign_key: { to_table: :team_members }
      t.references :co_author, foreign_key: { to_table: :team_members }
      t.string :author_name
      t.string :author_title
      t.string :author_avatar
      t.jsonb :key_messages, default: []
      t.jsonb :body_translations, default: {}
      t.jsonb :appendix_translations, default: {}
      t.jsonb :supporters_translations, default: {}
      t.string :category
      t.text :twitter_embed
      t.datetime :published_at
      t.boolean :featured, default: false

      t.timestamps
    end
    add_index :memos, :slug, unique: true
    add_index :memos, :category
    add_index :memos, :published_at
    add_index :memos, :featured
  end
end
