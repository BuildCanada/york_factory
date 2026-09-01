class CreateSocialMediaAccountDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_social_media_account_daily_metrics do |t|
      t.references :social_media_account, null: false,
        foreign_key: { to_table: :metrics_social_media_accounts, on_delete: :cascade },
        index: false
      t.date :date, null: false
      t.bigint :impressions
      t.bigint :unique_impressions
      t.bigint :reach
      t.bigint :views
      t.bigint :likes
      t.bigint :comments
      t.bigint :shares
      t.bigint :saves
      t.bigint :clicks
      t.decimal :engagement_rate, precision: 18, scale: 10
      t.bigint :organic_followers_gained
      t.bigint :paid_followers_gained
      t.datetime :scraped_at, null: false
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_social_media_account_daily_metrics,
      [ :social_media_account_id, :date ], unique: true,
      name: "ux_social_media_account_daily_metrics_date"
  end
end
