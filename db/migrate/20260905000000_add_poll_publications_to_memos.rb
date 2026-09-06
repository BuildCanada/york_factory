class AddPollPublicationsToMemos < ActiveRecord::Migration[8.1]
  def change
    add_column :memos, :content_kind, :string, null: false, default: "memo"
    add_index :memos, :content_kind
    add_column :memos, :survey_slug, :string
    add_column :memos, :survey_campaign_id, :string
    add_column :memos, :pollster, :string
    add_column :memos, :sample_size, :integer
    add_column :memos, :fieldwork_start, :date
    add_column :memos, :fieldwork_end, :date
    %i[en fr].each do |locale|
      %i[methodology news_release subscriber_email].each do |field|
        add_column :memos, "#{field}_md_#{locale}", :text
      end
      add_column :memos, "email_subject_#{locale}", :string
      add_column :memos, "tweet_#{locale}", :text
    end
  end
end
