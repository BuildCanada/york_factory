class CreateMetricsSocialMediaAnalytics < ActiveRecord::Migration[8.1]
  def change
    create_table "metrics_social_media_accounts" do |t|
      t.string :zernio_account_id, null: false
      t.string :zernio_profile_id, null: false
      t.string :profile_name, null: false
      t.string :platform, null: false
      t.string :account_key, null: false
      t.string :username, null: false
      t.string :display_name
      t.string :profile_url
      t.boolean :enabled, null: false, default: true
      t.datetime :source_updated_at
      t.timestamps
    end

    add_index "metrics_social_media_accounts", :zernio_account_id,
      unique: true, name: "ux_social_media_accounts_zernio_id"
    add_index "metrics_social_media_accounts", [ :platform, :account_key ],
      name: "idx_social_media_accounts_platform_key"

    create_table "metrics_social_media_account_metric_snapshots" do |t|
      t.references :social_media_account, null: false,
        foreign_key: { to_table: "metrics_social_media_accounts", on_delete: :cascade },
        index: false
      t.datetime :observed_at, null: false
      t.datetime :scraped_at, null: false
      t.bigint :followers_count
      t.timestamps
    end

    add_index "metrics_social_media_account_metric_snapshots",
      [ :social_media_account_id, :observed_at ], unique: true,
      name: "ux_social_media_account_snapshots_observed"

    create_table "metrics_social_media_posts" do |t|
      t.references :social_media_account, null: false,
        foreign_key: { to_table: "metrics_social_media_accounts", on_delete: :cascade },
        index: false
      t.references :social_post, null: true,
        foreign_key: { to_table: :social_posts, on_delete: :nullify },
        index: false
      t.string :zernio_post_id, null: false
      t.string :late_post_id
      t.string :platform_post_id
      t.string :platform, null: false
      t.string :account_username
      t.string :status, null: false
      t.text :content
      t.string :platform_post_url
      t.string :thumbnail_url
      t.string :media_type
      t.datetime :published_at
      t.datetime :scheduled_for
      t.boolean :external, null: false, default: false
      t.boolean :ad, null: false, default: false
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index "metrics_social_media_posts", [ :zernio_post_id, :social_media_account_id ],
      unique: true, name: "ux_social_media_posts_zernio_account"
    add_index "metrics_social_media_posts", [ :social_media_account_id, :published_at ],
      name: "idx_social_media_posts_account_published"
    add_index "metrics_social_media_posts", :social_post_id,
      name: "idx_social_media_posts_social_post"
    add_index "metrics_social_media_posts", [ :platform, :platform_post_id ],
      name: "idx_social_media_posts_platform_post"

    create_table "metrics_social_media_post_metric_snapshots" do |t|
      t.references :social_media_post, null: false,
        foreign_key: { to_table: "metrics_social_media_posts", on_delete: :cascade },
        index: false
      t.datetime :observed_at, null: false
      t.datetime :scraped_at, null: false
      t.bigint :impressions, null: false, default: 0
      t.bigint :reach, null: false, default: 0
      t.bigint :likes, null: false, default: 0
      t.bigint :comments, null: false, default: 0
      t.bigint :shares, null: false, default: 0
      t.bigint :saves, null: false, default: 0
      t.bigint :clicks, null: false, default: 0
      t.bigint :views, null: false, default: 0
      t.bigint :follows, null: false, default: 0
      t.bigint :reels_average_watch_time, null: false, default: 0
      t.bigint :reels_total_watch_time, null: false, default: 0
      t.decimal :video_duration_seconds, precision: 12, scale: 3
      t.decimal :engagement_rate, precision: 12, scale: 6
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index "metrics_social_media_post_metric_snapshots",
      [ :social_media_post_id, :observed_at ], unique: true,
      name: "ux_social_media_post_snapshots_observed"

    %i[
      metrics_twitter_stats metrics_linkedin_stats metrics_tiktok_stats
      metrics_instagram_stats
    ].each do |table|
      add_reference table, :social_media_account, null: true, index: true
      add_foreign_key table, :metrics_social_media_accounts,
        column: :social_media_account_id, on_delete: :nullify
    end
  end
end
