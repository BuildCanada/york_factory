class CreateTools < ActiveRecord::Migration[8.1]
  def change
    create_table :tools do |t|
      t.string :slug, null: false
      t.jsonb :title_translations, default: {}
      t.jsonb :description_translations, default: {}
      t.string :url
      t.boolean :featured, default: false
      t.integer :position, default: 0
      t.string :accent_color
      t.string :size, default: "small"

      t.timestamps
    end
    add_index :tools, :slug, unique: true
  end
end
