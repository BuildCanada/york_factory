class CreateWarehouseKpiDocumentsAndCitations < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.kpi_documents (
        id bigserial PRIMARY KEY,
        jurisdiction_id bigint NOT NULL REFERENCES warehouse.jurisdictions(id),
        organization_id bigint REFERENCES warehouse.organizations(id),
        raw_ingestion_id bigint REFERENCES warehouse.raw_ingestions(id),
        fiscal_year integer NOT NULL,
        published_at date,
        published_at_source varchar,
        source_page_url varchar,
        doc_url varchar NOT NULL,
        doc_title varchar,
        doc_type varchar,
        filepath varchar,
        content_hash varchar,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT kpi_documents_published_at_source_check
          CHECK (published_at_source IS NULL OR published_at_source IN
            ('pdf_metadata','http_last_modified','council_schedule',
             'discovered_at_fallback','manual'))
      )
    SQL

    add_index "warehouse.kpi_documents", :doc_url, unique: true
    add_index "warehouse.kpi_documents", [ :jurisdiction_id, :fiscal_year ],
              name: "idx_kpi_documents_jurisdiction_year"
    add_index "warehouse.kpi_documents", :organization_id,
              name: "idx_kpi_documents_organization"
    add_index "warehouse.kpi_documents", :content_hash

    # Now that kpi_documents exists, add the deferred FK on organization_lineages.
    execute <<~SQL
      ALTER TABLE warehouse.organization_lineages
        ADD CONSTRAINT fk_organization_lineages_acknowledged_doc
          FOREIGN KEY (acknowledged_in_document_id) REFERENCES warehouse.kpi_documents(id)
    SQL

    execute <<~SQL
      CREATE TABLE warehouse.measure_citations (
        id bigserial PRIMARY KEY,
        measure_id bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        measurement_year integer NOT NULL,
        value_type varchar NOT NULL,
        value_numeric double precision,
        value_text text,
        value_raw_text text,
        period_basis varchar NOT NULL DEFAULT 'full_year',
        document_id bigint NOT NULL REFERENCES warehouse.kpi_documents(id),
        page_number integer,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT measure_citations_value_type_check
          CHECK (value_type IN ('actual','target','projected','plan','budget')),
        CONSTRAINT measure_citations_period_basis_check
          CHECK (period_basis IN ('full_year','ytd_q1','ytd_q2','ytd_q3','as_of_date'))
      )
    SQL

    add_index "warehouse.measure_citations",
              [ :measure_id, :measurement_year, :value_type, :period_basis, :document_id ],
              unique: true,
              name: "idx_measure_citations_unique"
    add_index "warehouse.measure_citations", [ :measure_id, :measurement_year ],
              name: "idx_measure_citations_measure_year"
    add_index "warehouse.measure_citations", :document_id,
              name: "idx_measure_citations_document"

    execute <<~SQL
      CREATE TABLE warehouse.measure_lineages (
        id bigserial PRIMARY KEY,
        predecessor_id bigint NOT NULL REFERENCES warehouse.measures(id),
        successor_id bigint NOT NULL REFERENCES warehouse.measures(id),
        transition_year integer NOT NULL,
        transition_kind varchar NOT NULL,
        acknowledged_in_document_id bigint REFERENCES warehouse.kpi_documents(id),
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT measure_lineages_distinct CHECK (predecessor_id <> successor_id),
        CONSTRAINT measure_lineages_kind_check
          CHECK (transition_kind IN
            ('rename','methodology_revision','split','merge','unit_change','scope_change','revived'))
      )
    SQL

    add_index "warehouse.measure_lineages",
              [ :predecessor_id, :successor_id, :transition_year, :transition_kind ],
              unique: true,
              name: "idx_measure_lineages_unique"
    add_index "warehouse.measure_lineages", :predecessor_id,
              name: "idx_measure_lineages_predecessor"
    add_index "warehouse.measure_lineages", :successor_id,
              name: "idx_measure_lineages_successor"
  end

  def down
    drop_table "warehouse.measure_lineages"
    drop_table "warehouse.measure_citations"
    execute "ALTER TABLE warehouse.organization_lineages DROP CONSTRAINT IF EXISTS fk_organization_lineages_acknowledged_doc"
    drop_table "warehouse.kpi_documents"
  end
end
