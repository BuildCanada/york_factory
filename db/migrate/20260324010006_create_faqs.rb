class CreateFaqs < ActiveRecord::Migration[8.1]
  def change
    create_table :faqs do |t|
      t.text :question_en
      t.text :question_fr
      t.text :answer_text_en
      t.text :answer_text_fr
      t.string :link_text
      t.string :link_href
      t.integer :position, default: 0
      t.datetime :published_at

      t.timestamps
    end
    add_index :faqs, :position
  end
end
