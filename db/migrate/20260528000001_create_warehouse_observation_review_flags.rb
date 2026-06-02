class CreateWarehouseObservationReviewFlags < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.observation_review_flags (
        id bigserial PRIMARY KEY,
        extracted_observation_id bigint NOT NULL
          REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE,
        flag_type varchar NOT NULL,
        severity  varchar NOT NULL DEFAULT 'medium',
        message   text    NOT NULL,
        evidence  text,
        resolved_at      timestamptz,
        resolved_by      varchar,
        resolution_notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT observation_review_flags_severity_check
          CHECK (severity IN ('low','medium','high','critical')),
        CONSTRAINT observation_review_flags_resolved_pair
          CHECK ((resolved_at IS NULL) = (resolved_by IS NULL))
      )
    SQL

    add_index "warehouse.observation_review_flags", :extracted_observation_id,
              name: "idx_observation_review_flags_observation"
    add_index "warehouse.observation_review_flags", :flag_type,
              name: "idx_observation_review_flags_type"
    add_index "warehouse.observation_review_flags", :resolved_at,
              where: "resolved_at IS NULL",
              name: "idx_observation_review_flags_open"
    add_index "warehouse.observation_review_flags", :severity,
              where: "resolved_at IS NULL",
              name: "idx_observation_review_flags_open_severity"
  end

  def down
    drop_table "warehouse.observation_review_flags"
  end
end
