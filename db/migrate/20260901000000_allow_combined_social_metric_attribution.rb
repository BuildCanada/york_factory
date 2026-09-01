class AllowCombinedSocialMetricAttribution < ActiveRecord::Migration[8.1]
  def up
    change_column_null :metrics_social_metric_observations, :paid, true

    execute <<~SQL.squish
      DELETE FROM metrics_meta_account_insights
      WHERE metric_name IN ('reach_organic', 'reach_paid')
    SQL

    execute <<~SQL.squish
      UPDATE metrics_social_metric_observations
      SET active = FALSE, updated_at = CURRENT_TIMESTAMP
      WHERE source_record_type = 'Metrics::MetaAccountInsight'
        AND source_metric_name IN ('reach_organic', 'reach_paid')
        AND active = TRUE
    SQL
  end

  def down
    change_column_null :metrics_social_metric_observations, :paid, false, false
  end
end
