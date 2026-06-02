class CreateWarehouseSourceFootnotes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.source_footnotes (
        id bigserial PRIMARY KEY,
        document_id     bigint NOT NULL REFERENCES warehouse.kpi_documents(id) ON DELETE CASCADE,
        agent_run_id    bigint REFERENCES warehouse.agent_runs(id) ON DELETE SET NULL,
        page            integer,
        marker          varchar,
        footnote_text   text NOT NULL,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.source_footnotes", :document_id, name: "idx_source_footnotes_document"
    add_index "warehouse.source_footnotes", [ :document_id, :page, :marker ],
              name: "idx_source_footnotes_document_marker"

    execute <<~SQL
      CREATE TABLE warehouse.observation_footnotes (
        extracted_observation_id bigint NOT NULL
          REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE,
        source_footnote_id bigint NOT NULL
          REFERENCES warehouse.source_footnotes(id) ON DELETE CASCADE,
        created_at timestamp(6) NOT NULL DEFAULT now(),
        PRIMARY KEY (extracted_observation_id, source_footnote_id)
      )
    SQL

    add_index "warehouse.observation_footnotes", :source_footnote_id,
              name: "idx_observation_footnotes_footnote"

    execute <<~SQL
      CREATE TABLE warehouse.extraction_assertions (
        id bigserial PRIMARY KEY,
        extracted_observation_id bigint NOT NULL
          REFERENCES warehouse.extracted_observations(id) ON DELETE CASCADE,
        assertion_type varchar NOT NULL,
        assertion_text text NOT NULL,
        confidence numeric,
        evidence_quote text,
        source_page integer,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT extraction_assertions_confidence_range
          CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
      )
    SQL

    add_index "warehouse.extraction_assertions", :extracted_observation_id,
              name: "idx_extraction_assertions_observation"
    add_index "warehouse.extraction_assertions", :assertion_type,
              name: "idx_extraction_assertions_type"
  end

  def down
    drop_table "warehouse.extraction_assertions"
    drop_table "warehouse.observation_footnotes"
    drop_table "warehouse.source_footnotes"
  end
end
