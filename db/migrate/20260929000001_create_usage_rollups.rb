# Usage metering (docs/public-interface-design.md §6.3, §6.4 and WS-I).
#
# - usage_hourly: units and requests per account, key, operation and hour,
#   from the edge's Analytics Engine points; kept for 7 days.
# - usage_daily: the same per day, kept for good. The billing source.
# - usage_rollup_runs: each rollup's window, so the console can say how fresh
#   it is.
# - usage_quota_notices: the 80% and 100% emails, once per account, month and
#   threshold.
# - usage_reconciliations: daily units against the edge's AccountDO (0.5%).
# - billing_usage_records: units per account and day, ready to report to a
#   billing meter; nothing reports them yet (no Stripe calls).
#
# api_key_id is blank for OAuth callers (the edge meters them by account).
# The unique indexes coalesce it, so one row holds each group.
class CreateUsageRollups < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_hourly do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :api_key_id
      t.string :operation, null: false
      t.timestamptz :hour_start, null: false
      t.bigint :requests, null: false, default: 0
      t.bigint :units, null: false, default: 0
      t.bigint :cache_hits, null: false, default: 0
      t.bigint :errors_4xx, null: false, default: 0
      t.bigint :errors_5xx, null: false, default: 0
      t.bigint :throttled, null: false, default: 0
      t.float :p95_ms
      t.timestamptz :rolled_up_at, null: false
    end
    add_index :usage_hourly, "account_id, COALESCE(api_key_id, 0), operation, hour_start", unique: true, name: "index_usage_hourly_on_group"
    add_index :usage_hourly, :hour_start
    add_index :usage_hourly, %i[api_key_id hour_start]

    create_table :usage_daily do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :api_key_id
      t.string :operation, null: false
      t.date :day, null: false
      t.bigint :requests, null: false, default: 0
      t.bigint :units, null: false, default: 0
      t.bigint :cache_hits, null: false, default: 0
      t.bigint :errors_4xx, null: false, default: 0
      t.bigint :errors_5xx, null: false, default: 0
      t.bigint :throttled, null: false, default: 0
      t.timestamptz :rolled_up_at, null: false
    end
    add_index :usage_daily, "account_id, COALESCE(api_key_id, 0), operation, day", unique: true, name: "index_usage_daily_on_group"
    add_index :usage_daily, %i[account_id day]
    add_index :usage_daily, %i[api_key_id day]
    add_index :usage_daily, %i[operation day]
    add_index :usage_daily, :day

    create_table :usage_rollup_runs do |t|
      t.timestamptz :window_start, null: false
      t.timestamptz :window_end, null: false
      t.string :source, null: false
      t.integer :hourly_rows, null: false, default: 0
      t.integer :daily_rows, null: false, default: 0
      t.timestamptz :finished_at, null: false
    end
    add_index :usage_rollup_runs, :finished_at

    create_table :usage_quota_notices do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :period, null: false
      t.integer :threshold, null: false
      t.bigint :units, null: false
      t.bigint :quota, null: false
      t.timestamptz :sent_at, null: false
    end
    add_index :usage_quota_notices, %i[account_id period threshold], unique: true, name: "index_usage_quota_notices_once"

    create_table :usage_reconciliations do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :day, null: false
      t.bigint :rollup_units, null: false
      t.bigint :edge_units, null: false
      t.float :drift, null: false
      t.boolean :alerted, null: false, default: false
      t.timestamptz :checked_at, null: false
    end
    add_index :usage_reconciliations, %i[account_id day], unique: true
    add_index :usage_reconciliations, %i[alerted day]

    create_table :billing_usage_records do |t|
      t.references :account, null: false, foreign_key: { on_delete: :restrict }, index: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.bigint :units, null: false
      t.string :meter, null: false, default: "api_units"
      t.string :status, null: false, default: "pending"
      t.string :idempotency_key, null: false
      t.string :external_id
      t.timestamptz :reported_at
      t.timestamps
    end
    add_index :billing_usage_records, :idempotency_key, unique: true
    add_index :billing_usage_records, %i[account_id period_start], unique: true
    add_index :billing_usage_records, :status
    add_check_constraint :billing_usage_records, "status IN ('pending','reported','skipped')", name: "billing_usage_records_status"

    add_column :accounts, :stripe_subscription_id, :string
    add_column :accounts, :stripe_subscription_item_id, :string
  end
end
