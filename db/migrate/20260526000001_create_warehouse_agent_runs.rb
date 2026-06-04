class CreateWarehouseAgentRuns < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.agent_runs (
        id bigserial PRIMARY KEY,
        agent_name varchar NOT NULL,
        agent_version varchar,
        input_params jsonb NOT NULL DEFAULT '{}'::jsonb,
        status varchar NOT NULL DEFAULT 'running',
        started_at timestamp(6) NOT NULL,
        finished_at timestamp(6),
        triggered_by varchar,
        report text,
        summary jsonb,
        error_message text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT agent_runs_status_check
          CHECK (status IN ('running','completed','failed','cancelled'))
      )
    SQL

    add_index "warehouse.agent_runs", [ :agent_name, :started_at ],
              name: "idx_agent_runs_agent_started", order: { started_at: :desc }
    add_index "warehouse.agent_runs", :status

    execute <<~SQL
      ALTER TABLE warehouse.kpi_documents
        ADD COLUMN agent_run_id bigint REFERENCES warehouse.agent_runs(id);
      ALTER TABLE warehouse.measures
        ADD COLUMN agent_run_id bigint REFERENCES warehouse.agent_runs(id);
      ALTER TABLE warehouse.measure_citations
        ADD COLUMN agent_run_id bigint REFERENCES warehouse.agent_runs(id);
    SQL

    add_index "warehouse.kpi_documents", :agent_run_id,
              where: "agent_run_id IS NOT NULL",
              name: "idx_kpi_documents_agent_run"
    add_index "warehouse.measures", :agent_run_id,
              where: "agent_run_id IS NOT NULL",
              name: "idx_measures_agent_run"
    add_index "warehouse.measure_citations", :agent_run_id,
              where: "agent_run_id IS NOT NULL",
              name: "idx_measure_citations_agent_run"
  end

  def down
    execute <<~SQL
      ALTER TABLE warehouse.measure_citations DROP COLUMN agent_run_id;
      ALTER TABLE warehouse.measures          DROP COLUMN agent_run_id;
      ALTER TABLE warehouse.kpi_documents     DROP COLUMN agent_run_id;
    SQL
    drop_table "warehouse.agent_runs"
  end
end
