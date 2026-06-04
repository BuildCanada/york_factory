class CreateWarehouseMetricVersionsAndAliases < ActiveRecord::Migration[8.1]
  ALIAS_KINDS = %w[raw_text measure_equivalence].freeze

  def up
    execute <<~SQL
      CREATE TABLE warehouse.metric_versions (
        id bigserial PRIMARY KEY,
        measure_id bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        version_label varchar NOT NULL,
        definition    text NOT NULL,
        methodology   text,
        active_from   date,
        active_to     date,
        source_id     bigint REFERENCES warehouse.sources(id),
        document_id   bigint REFERENCES warehouse.kpi_documents(id),
        breaking_change boolean NOT NULL DEFAULT false,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT metric_versions_active_range
          CHECK (active_to IS NULL OR active_from IS NULL OR active_to >= active_from)
      )
    SQL

    add_index "warehouse.metric_versions", [ :measure_id, :version_label ], unique: true,
              name: "idx_metric_versions_measure_label"
    add_index "warehouse.metric_versions", :measure_id, name: "idx_metric_versions_measure"
    add_index "warehouse.metric_versions", :document_id, name: "idx_metric_versions_document"

    execute <<~SQL
      CREATE TABLE warehouse.metric_aliases (
        id bigserial PRIMARY KEY,
        measure_id bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        alias_text varchar NOT NULL,
        kind varchar NOT NULL DEFAULT 'raw_text',
        source_id   bigint REFERENCES warehouse.sources(id),
        document_id bigint REFERENCES warehouse.kpi_documents(id),
        canonical_measure_id bigint REFERENCES warehouse.measures(id),
        valid_from date,
        valid_to   date,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT metric_aliases_kind_check
          CHECK (kind IN (#{ALIAS_KINDS.map { |s| "'#{s}'" }.join(',')})),
        CONSTRAINT metric_aliases_equivalence_target
          CHECK (
            (kind <> 'measure_equivalence')
            OR (canonical_measure_id IS NOT NULL AND canonical_measure_id <> measure_id)
          )
      )
    SQL

    add_index "warehouse.metric_aliases", [ :kind, :alias_text ],
              name: "idx_metric_aliases_kind_text"
    add_index "warehouse.metric_aliases", :measure_id, name: "idx_metric_aliases_measure"
    add_index "warehouse.metric_aliases", :canonical_measure_id, name: "idx_metric_aliases_canonical_measure"
    add_index "warehouse.metric_aliases", [ :measure_id, :alias_text ], unique: true,
              where: "kind = 'raw_text'",
              name: "idx_metric_aliases_raw_text_unique"
    add_index "warehouse.metric_aliases", [ :measure_id, :canonical_measure_id ], unique: true,
              where: "kind = 'measure_equivalence'",
              name: "idx_metric_aliases_equivalence_unique"

    # Add metric_version_id reference on observations.
    execute "ALTER TABLE warehouse.extracted_observations ADD COLUMN metric_version_id bigint REFERENCES warehouse.metric_versions(id)"
    execute "ALTER TABLE warehouse.canonical_observations ADD COLUMN metric_version_id bigint REFERENCES warehouse.metric_versions(id)"
    add_index "warehouse.extracted_observations", :metric_version_id,
              name: "idx_extracted_observations_metric_version"
    add_index "warehouse.canonical_observations", :metric_version_id,
              name: "idx_canonical_observations_metric_version"
  end

  def down
    execute "ALTER TABLE warehouse.extracted_observations DROP COLUMN IF EXISTS metric_version_id"
    execute "ALTER TABLE warehouse.canonical_observations DROP COLUMN IF EXISTS metric_version_id"
    drop_table "warehouse.metric_aliases"
    drop_table "warehouse.metric_versions"
  end
end
