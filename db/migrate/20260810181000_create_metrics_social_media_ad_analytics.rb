class CreateMetricsSocialMediaAdAnalytics < ActiveRecord::Migration[8.1]
  def change
    add_column :metrics_social_media_accounts, :ads_status, :string

    create_table :metrics_social_media_ad_accounts do |t|
      t.references :social_media_account, null: false,
        foreign_key: { to_table: :metrics_social_media_accounts, on_delete: :cascade }, index: false
      t.string :platform_ad_account_id, null: false
      t.string :platform, null: false
      t.string :name
      t.string :business_name
      t.string :status
      t.string :currency
      t.string :timezone_name
      t.decimal :timezone_offset_hours, precision: 8, scale: 2
      t.decimal :minimum_daily_budget, precision: 18, scale: 6
      t.boolean :selectable
      t.string :unusable_reason
      t.boolean :backfill_pending, null: false, default: false
      t.jsonb :source_payload, null: false, default: {}
      t.jsonb :analytics_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_social_media_ad_accounts,
      [ :social_media_account_id, :platform_ad_account_id ], unique: true,
      name: "ux_metrics_ad_accounts_source_id"

    create_table :metrics_social_media_ad_campaigns do |t|
      t.references :social_media_account, null: false,
        foreign_key: { to_table: :metrics_social_media_accounts, on_delete: :cascade }, index: false
      t.references :ad_account,
        foreign_key: { to_table: :metrics_social_media_ad_accounts, on_delete: :nullify }, index: false
      t.string :platform_campaign_id, null: false
      t.string :platform_ad_account_id
      t.string :platform, null: false
      t.string :name
      t.string :status
      t.string :currency
      t.string :channel_type
      t.integer :ad_count
      t.boolean :external, null: false, default: false
      t.datetime :platform_created_at
      t.datetime :earliest_ad_at
      t.datetime :latest_ad_at
      t.boolean :backfill_pending, null: false, default: false
      t.jsonb :budget_payload, null: false, default: {}
      t.jsonb :metrics_payload, null: false, default: {}
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_social_media_ad_campaigns,
      [ :social_media_account_id, :platform, :platform_campaign_id ], unique: true,
      name: "ux_metrics_ad_campaigns_source_id"
    add_index :metrics_social_media_ad_campaigns, :ad_account_id,
      name: "idx_metrics_ad_campaigns_account"

    create_table :metrics_social_media_ads do |t|
      t.references :social_media_account, null: false,
        foreign_key: { to_table: :metrics_social_media_accounts, on_delete: :cascade }, index: false
      t.references :ad_account,
        foreign_key: { to_table: :metrics_social_media_ad_accounts, on_delete: :nullify }, index: false
      t.references :campaign,
        foreign_key: { to_table: :metrics_social_media_ad_campaigns, on_delete: :nullify }, index: false
      t.string :zernio_ad_id, null: false
      t.string :platform_ad_id
      t.string :platform_ad_account_id
      t.string :platform_campaign_id
      t.string :platform_ad_set_id
      t.string :platform, null: false
      t.string :name
      t.string :ad_set_name
      t.string :status
      t.string :goal
      t.string :ad_type
      t.string :currency
      t.boolean :external, null: false, default: false
      t.datetime :platform_created_at
      t.datetime :source_updated_at
      t.datetime :last_synced_at
      t.boolean :backfill_pending, null: false, default: false
      t.jsonb :creative_payload, null: false, default: {}
      t.jsonb :metrics_payload, null: false, default: {}
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index :metrics_social_media_ads, :zernio_ad_id, unique: true,
      name: "ux_metrics_ads_zernio_id"
    add_index :metrics_social_media_ads, :ad_account_id, name: "idx_metrics_ads_account"
    add_index :metrics_social_media_ads, :campaign_id, name: "idx_metrics_ads_campaign"

    create_daily_metrics_table :metrics_social_media_ad_account_daily_metrics,
      :ad_account, :metrics_social_media_ad_accounts
    create_daily_metrics_table :metrics_social_media_ad_campaign_daily_metrics,
      :campaign, :metrics_social_media_ad_campaigns
    create_daily_metrics_table :metrics_social_media_ad_daily_metrics,
      :ad, :metrics_social_media_ads
  end

  private

  def create_daily_metrics_table(table, owner, target_table)
    create_table table do |t|
      t.references owner, null: false,
        foreign_key: { to_table: target_table, on_delete: :cascade }, index: false
      t.date :date, null: false
      t.decimal :spend, precision: 18, scale: 6
      t.bigint :impressions
      t.bigint :reach
      t.bigint :clicks
      t.bigint :engagements
      t.decimal :conversions, precision: 18, scale: 6
      t.decimal :conversion_value, precision: 18, scale: 6
      t.decimal :ctr, precision: 18, scale: 8
      t.decimal :cpc, precision: 18, scale: 8
      t.decimal :cpm, precision: 18, scale: 8
      t.decimal :cost_per_conversion, precision: 18, scale: 8
      t.decimal :roas, precision: 18, scale: 8
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end

    add_index table, [ "#{owner}_id", :date ], unique: true,
      name: "ux_#{table.to_s.sub('metrics_social_media_', '')}_date"
  end
end
