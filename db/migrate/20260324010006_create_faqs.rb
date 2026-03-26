class CreateFaqs < ActiveRecord::Migration[8.1]
  def change
    create_table :faqs do |t|
      t.jsonb :question_translations, default: {}
      t.jsonb :answer_translations, default: {}
      t.jsonb :answer_text_translations, default: {}
      t.string :link_text
      t.string :link_href
      t.integer :position, default: 0

      t.timestamps
    end
    add_index :faqs, :position
  end
end
