class DropActionTextRichTexts < ActiveRecord::Migration[8.1]
  def up
    drop_table :action_text_rich_texts, if_exists: true
  end

  def down
    create_table :action_text_rich_texts do |t|
      t.string     :name, null: false
      t.text       :body, size: :long
      t.references :record, null: false, polymorphic: true, index: false
      t.timestamps

      t.index [ :record_type, :record_id, :name ], name: "index_action_text_rich_texts_uniqueness", unique: true
    end
  end
end
