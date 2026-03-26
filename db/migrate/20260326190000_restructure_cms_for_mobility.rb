class RestructureCmsForMobility < ActiveRecord::Migration[8.1]
  def change
    # Posts: add _en/_fr columns, remove JSONB translations
    add_column :posts, :title_en, :string
    add_column :posts, :title_fr, :string
    add_column :posts, :summary_en, :text
    add_column :posts, :summary_fr, :text
    remove_column :posts, :title_translations, :jsonb, default: {}
    remove_column :posts, :summary_translations, :jsonb, default: {}
    remove_column :posts, :body_translations, :jsonb, default: {}

    # Memos: add _en/_fr columns, remove JSONB translations
    add_column :memos, :title_en, :string
    add_column :memos, :title_fr, :string
    add_column :memos, :description_en, :text
    add_column :memos, :description_fr, :text
    add_column :memos, :supporters_en, :text
    add_column :memos, :supporters_fr, :text
    add_column :memos, :key_messages_en, :jsonb, default: []
    add_column :memos, :key_messages_fr, :jsonb, default: []
    remove_column :memos, :title_translations, :jsonb, default: {}
    remove_column :memos, :description_translations, :jsonb, default: {}
    remove_column :memos, :body_translations, :jsonb, default: {}
    remove_column :memos, :appendix_translations, :jsonb, default: {}
    remove_column :memos, :supporters_translations, :jsonb, default: {}
    remove_column :memos, :key_messages, :jsonb, default: []

    # Builders: add _en/_fr columns, remove JSONB translations
    add_column :builders, :title_en, :string
    add_column :builders, :title_fr, :string
    add_column :builders, :byline_en, :text
    add_column :builders, :byline_fr, :text
    add_column :builders, :quote_en, :text
    add_column :builders, :quote_fr, :text
    add_column :builders, :author_en, :string
    add_column :builders, :author_fr, :string
    remove_column :builders, :title_translations, :jsonb, default: {}
    remove_column :builders, :byline_translations, :jsonb, default: {}
    remove_column :builders, :quote_translations, :jsonb, default: {}
    remove_column :builders, :body_translations, :jsonb, default: {}
    remove_column :builders, :author_translations, :jsonb, default: {}

    # FAQs: add _en/_fr columns, remove JSONB translations
    add_column :faqs, :question_en, :text
    add_column :faqs, :question_fr, :text
    add_column :faqs, :answer_text_en, :text
    add_column :faqs, :answer_text_fr, :text
    remove_column :faqs, :question_translations, :jsonb, default: {}
    remove_column :faqs, :answer_translations, :jsonb, default: {}
    remove_column :faqs, :answer_text_translations, :jsonb, default: {}

    # FeedItems: add _en/_fr columns, remove JSONB translations
    add_column :feed_items, :title_en, :string
    add_column :feed_items, :title_fr, :string
    add_column :feed_items, :subtitle_en, :string
    add_column :feed_items, :subtitle_fr, :string
    remove_column :feed_items, :title_translations, :jsonb, default: {}
    remove_column :feed_items, :subtitle_translations, :jsonb, default: {}
    remove_column :feed_items, :body_translations, :jsonb, default: {}

    # Tools: add _en/_fr columns, remove JSONB translations
    add_column :tools, :title_en, :string
    add_column :tools, :title_fr, :string
    remove_column :tools, :title_translations, :jsonb, default: {}
    remove_column :tools, :description_translations, :jsonb, default: {}

    # TeamMembers: add _en/_fr columns, remove JSONB translations
    add_column :team_members, :title_en, :string
    add_column :team_members, :title_fr, :string
    remove_column :team_members, :title_translations, :jsonb, default: {}

    # Testimonials: add _en/_fr columns, remove JSONB translations
    add_column :testimonials, :quote_en, :text
    add_column :testimonials, :quote_fr, :text
    remove_column :testimonials, :quote_translations, :jsonb, default: {}
  end
end
