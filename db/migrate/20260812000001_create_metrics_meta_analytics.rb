class CreateMetricsMetaAnalytics < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_meta_accounts do |t|
      t.string :platform, null: false
      t.string :account_key, null: false
      t.string :platform_account_id, null: false
      t.string :username
      t.string :display_name
      t.datetime :last_synced_at
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_meta_accounts, [ :platform, :account_key ], unique: true
    add_index :metrics_meta_accounts, [ :platform, :platform_account_id ], unique: true,
      name: "ux_metrics_meta_accounts_platform_id"

    create_table :metrics_meta_account_insights do |t|
      t.references :meta_account, null: false,
        foreign_key: { to_table: :metrics_meta_accounts, on_delete: :cascade }
      t.string :metric_name, null: false
      t.string :period
      t.datetime :observed_at, null: false
      t.decimal :value_numeric, precision: 24, scale: 6
      t.jsonb :value_payload, null: false, default: {}
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_meta_account_insights,
      [ :meta_account_id, :metric_name, :period, :observed_at ], unique: true,
      name: "ux_metrics_meta_account_insights"

    create_table :metrics_meta_media do |t|
      t.references :meta_account, null: false,
        foreign_key: { to_table: :metrics_meta_accounts, on_delete: :cascade }
      t.string :platform_media_id, null: false
      t.string :media_type
      t.text :caption
      t.string :permalink
      t.datetime :published_at
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_meta_media, [ :meta_account_id, :platform_media_id ], unique: true,
      name: "ux_metrics_meta_media_account_id"

    create_table :metrics_meta_media_insights do |t|
      t.references :meta_medium, null: false,
        foreign_key: { to_table: :metrics_meta_media, on_delete: :cascade }
      t.string :metric_name, null: false
      t.string :period
      t.datetime :observed_at, null: false
      t.decimal :value_numeric, precision: 24, scale: 6
      t.jsonb :value_payload, null: false, default: {}
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_meta_media_insights,
      [ :meta_medium_id, :metric_name, :period, :observed_at ], unique: true,
      name: "ux_metrics_meta_media_insights"
  end
end
