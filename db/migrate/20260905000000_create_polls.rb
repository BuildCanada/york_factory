class CreatePolls < ActiveRecord::Migration[8.1]
  def change
    create_table :polls do |t|
      t.string :slug, null: false
      t.references :author, foreign_key: { to_table: :team_members }
      t.string :author_name
      t.string :author_title
      t.boolean :featured, default: false
      t.datetime :published_at
      t.text :twitter_embed
      t.string :survey_slug, null: false
      t.string :survey_campaign_id
      t.string :pollster
      t.integer :sample_size
      t.date :fieldwork_start
      t.date :fieldwork_end
      %i[en fr].each do |locale|
        t.string "title_#{locale}"
        t.jsonb "key_messages_#{locale}", default: []
        %i[body appendix methodology news_release subscriber_email].each do |field|
          t.text "#{field}_md_#{locale}"
        end
        t.string "email_subject_#{locale}"
        t.text "tweet_#{locale}"
      end
      t.timestamps
    end
    add_index :polls, :slug, unique: true
    add_index :polls, :published_at
  end
end
