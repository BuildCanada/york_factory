class CreateMetricsSubstackAnalytics < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_substack_publications do |t|
      t.string :account_key, null: false
      t.string :publication_id
      t.string :url, null: false
      t.string :subdomain
      t.string :name
      t.datetime :last_synced_at
      t.datetime :posts_backfilled_at
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_substack_publications, :account_key, unique: true
    add_index :metrics_substack_publications, :publication_id, unique: true,
      where: "publication_id IS NOT NULL"

    create_table :metrics_substack_posts do |t|
      t.references :substack_publication, null: false,
        foreign_key: { to_table: :metrics_substack_publications, on_delete: :cascade },
        index: false
      t.references :feed_substack_post, null: true,
        foreign_key: { to_table: :substack_posts, on_delete: :nullify },
        index: false
      t.string :substack_post_id, null: false
      t.string :publication_id
      t.string :slug
      t.string :title
      t.text :subtitle
      t.string :canonical_url
      t.string :audience
      t.string :post_type
      t.string :cover_image_url
      t.datetime :published_at
      t.boolean :published, null: false, default: false
      t.jsonb :source_payload, null: false, default: {}
      t.jsonb :details_payload, null: false, default: {}
      t.datetime :details_synced_at
      t.datetime :next_details_sync_at
      t.datetime :details_sync_enqueued_at
      t.timestamps
    end

    add_index :metrics_substack_posts,
      [ :substack_publication_id, :substack_post_id ], unique: true,
      name: "ux_metrics_substack_posts_publication_post"
    add_index :metrics_substack_posts, :feed_substack_post_id
    add_index :metrics_substack_posts, :next_details_sync_at,
      name: "idx_metrics_substack_posts_due_details"
    add_index :metrics_substack_posts, [ :substack_publication_id, :published_at ],
      name: "idx_metrics_substack_posts_published"

    create_table :metrics_substack_post_metric_snapshots do |t|
      t.references :substack_post, null: false,
        foreign_key: { to_table: :metrics_substack_posts, on_delete: :cascade },
        index: false
      t.string :snapshot_type, null: false
      t.datetime :observed_at, null: false
      t.datetime :scraped_at, null: false
      t.integer :day_number
      t.bigint :views
      t.bigint :cumulative_views
      t.bigint :opens
      t.bigint :opened
      t.decimal :open_rate, precision: 12, scale: 6
      t.bigint :clicks
      t.bigint :clicked
      t.decimal :click_through_rate, precision: 12, scale: 6
      t.bigint :delivered
      t.bigint :sent
      t.bigint :shares
      t.bigint :signups
      t.bigint :cumulative_signups
      t.bigint :subscribes
      t.bigint :cumulative_subscribes
      t.bigint :free_trials
      t.decimal :estimated_value, precision: 24, scale: 6
      t.decimal :engagement_rate, precision: 12, scale: 6
      t.bigint :downloads
      t.bigint :video_views
      t.decimal :video_minutes_watched, precision: 24, scale: 6
      t.jsonb :stats_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_substack_post_metric_snapshots,
      [ :substack_post_id, :snapshot_type, :observed_at ], unique: true,
      name: "ux_metrics_substack_post_snapshots"
  end
end
