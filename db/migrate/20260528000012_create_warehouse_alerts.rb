class CreateWarehouseAlerts < ActiveRecord::Migration[8.1]
  CONDITION_TYPES = %w[
    above below percent_change absolute_change missing_update
    rank_change new_definition new_component conflicting_source
  ].freeze
  SEVERITIES = %w[low medium high critical].freeze

  def up
    execute <<~SQL
      CREATE TABLE warehouse.alerts (
        id bigserial PRIMARY KEY,
        name varchar NOT NULL,
        measure_id bigint REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        geo_boundary_id bigint REFERENCES warehouse.geo_boundaries(id),
        jurisdiction_id bigint REFERENCES warehouse.jurisdictions(id),
        observed_organization_id bigint REFERENCES warehouse.organizations(id),

        condition_type varchar NOT NULL,
        threshold_value numeric,
        comparison_period varchar,
        severity varchar NOT NULL DEFAULT 'medium',
        enabled boolean NOT NULL DEFAULT true,

        notes text,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT alerts_condition_type_check
          CHECK (condition_type IN (#{CONDITION_TYPES.map { |s| "'#{s}'" }.join(',')})),
        CONSTRAINT alerts_severity_check
          CHECK (severity IN (#{SEVERITIES.map { |s| "'#{s}'" }.join(',')}))
      )
    SQL

    add_index "warehouse.alerts", :enabled, name: "idx_alerts_enabled"
    add_index "warehouse.alerts", :measure_id, name: "idx_alerts_measure"
    add_index "warehouse.alerts", :observed_organization_id, name: "idx_alerts_observed_org"

    execute <<~SQL
      CREATE TABLE warehouse.alert_events (
        id bigserial PRIMARY KEY,
        alert_id bigint NOT NULL REFERENCES warehouse.alerts(id) ON DELETE CASCADE,
        triggered_at timestamptz NOT NULL DEFAULT now(),
        canonical_observation_id bigint REFERENCES warehouse.canonical_observations(id) ON DELETE SET NULL,
        observed_value numeric,
        comparison_value numeric,
        message text,
        details jsonb,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.alert_events", :alert_id, name: "idx_alert_events_alert"
    add_index "warehouse.alert_events", :triggered_at, name: "idx_alert_events_triggered_at"
  end

  def down
    drop_table "warehouse.alert_events"
    drop_table "warehouse.alerts"
  end
end
