class CreateWarehouseReviewDecisions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.review_decisions (
        id bigserial PRIMARY KEY,
        extracted_observation_id bigint NOT NULL
          REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE,
        reviewer varchar NOT NULL,
        decision varchar NOT NULL,
        previous_value jsonb,
        new_value      jsonb,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT review_decisions_decision_check
          CHECK (decision IN ('approved','rejected','edited','needs_more_info'))
      )
    SQL

    add_index "warehouse.review_decisions", :extracted_observation_id,
              name: "idx_review_decisions_observation"
    add_index "warehouse.review_decisions", :reviewer,
              name: "idx_review_decisions_reviewer"
    add_index "warehouse.review_decisions", :created_at,
              name: "idx_review_decisions_created"
  end

  def down
    drop_table "warehouse.review_decisions"
  end
end
