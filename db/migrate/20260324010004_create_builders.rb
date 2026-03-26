class CreateBuilders < ActiveRecord::Migration[8.1]
  def change
    create_table :builders do |t|
      t.string :slug, null: false
      t.jsonb :title_translations, default: {}
      t.jsonb :byline_translations, default: {}
      t.jsonb :quote_translations, default: {}
      t.jsonb :body_translations, default: {}
      t.jsonb :author_translations, default: {}

      t.timestamps
    end
    add_index :builders, :slug, unique: true
  end
end
