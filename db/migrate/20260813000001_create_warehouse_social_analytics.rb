class CreateWarehouseSocialAnalytics < ActiveRecord::Migration[8.1]
  def up
    create_table "warehouse.social_entities", id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :parent_id
      t.string :entity_type, null: false
      t.string :platform, null: false
      t.string :account_key, null: false
      t.string :external_id
      t.string :name
      t.string :username
      t.string :url
      t.string :media_type
      t.datetime :published_at
      t.string :source, null: false
      t.string :source_record_type, null: false
      t.string :source_record_id, null: false
      t.boolean :active, null: false, default: true
      t.datetime :source_updated_at, null: false
      t.datetime :refreshed_at, null: false
      t.timestamps
    end

    add_index "warehouse.social_entities", :parent_id
    add_index "warehouse.social_entities", [ :platform, :account_key, :entity_type ],
      name: "idx_social_entities_platform_account_type"
    add_index "warehouse.social_entities", [ :source_record_type, :source_record_id ],
      name: "idx_social_entities_source_record"

    add_foreign_key "warehouse.social_entities", "warehouse.social_entities",
      column: :parent_id, primary_key: :id, on_delete: :cascade

    create_table "warehouse.social_metric_observations", id: false do |t|
      t.string :id, null: false, primary_key: true
      t.string :social_entity_id, null: false
      t.string :entity_type, null: false
      t.string :platform, null: false
      t.string :account_key, null: false
      t.string :source, null: false
      t.string :source_record_type, null: false
      t.string :source_record_id, null: false
      t.string :grain, null: false
      t.string :metric_name, null: false
      t.string :source_metric_name, null: false
      t.decimal :value, precision: 30, scale: 8, null: false
      t.string :unit, null: false, default: "count"
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.datetime :observed_at, null: false
      t.boolean :cumulative, null: false, default: false
      t.boolean :paid, null: false, default: false
      t.boolean :reporting_source, null: false, default: false
      t.boolean :fallback_metric, null: false, default: false
      t.boolean :current_value, null: false, default: true
      t.boolean :active, null: false, default: true
      t.datetime :source_updated_at, null: false
      t.datetime :refreshed_at, null: false
      t.timestamps
    end

    add_index "warehouse.social_metric_observations", :social_entity_id,
      name: "idx_social_metric_observations_entity"
    add_index "warehouse.social_metric_observations",
      [ :metric_name, :period_start, :platform, :account_key ],
      name: "idx_social_metrics_reporting"
    add_index "warehouse.social_metric_observations",
      [ :reporting_source, :current_value, :paid ],
      name: "idx_social_metrics_reportable"
    add_index "warehouse.social_metric_observations", [ :source, :source_record_type ],
      name: "idx_social_metrics_source"
    add_index "warehouse.social_metric_observations", :updated_at,
      name: "idx_social_metrics_updated_at"

    add_foreign_key "warehouse.social_metric_observations", "warehouse.social_entities",
      column: :social_entity_id, primary_key: :id, on_delete: :cascade
  end

  def down
    drop_table "warehouse.social_metric_observations"
    drop_table "warehouse.social_entities"
  end
end
