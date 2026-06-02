class CreateWarehouseCanonicalObservations < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.canonical_observations (
        id bigserial PRIMARY KEY,
        extracted_observation_id bigint NOT NULL REFERENCES warehouse.extracted_observations(id) ON DELETE RESTRICT,
        measure_id bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        document_id bigint NOT NULL REFERENCES warehouse.kpi_documents(id),

        reporting_organization_id   bigint REFERENCES warehouse.organizations(id),
        responsible_organization_id bigint REFERENCES warehouse.organizations(id),
        observed_organization_id    bigint REFERENCES warehouse.organizations(id),
        geo_boundary_id bigint REFERENCES warehouse.geo_boundaries(id),
        jurisdiction_id bigint REFERENCES warehouse.jurisdictions(id),

        measurement_year integer NOT NULL,
        period_start date,
        period_end   date,
        period_type  varchar,
        value_type   varchar NOT NULL,
        period_basis varchar NOT NULL DEFAULT 'full_year',

        value_numeric double precision,
        value_text    text,
        unit_id bigint REFERENCES warehouse.units(id),

        vintage_date date,
        status varchar NOT NULL DEFAULT 'reported',
        is_total    boolean NOT NULL DEFAULT false,
        is_residual boolean NOT NULL DEFAULT false,

        approved_by varchar,
        approved_at timestamptz NOT NULL DEFAULT now(),
        notes text,

        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,

        CONSTRAINT canonical_observations_value_type_check
          CHECK (value_type IN ('actual','target','projected','plan','budget')),
        CONSTRAINT canonical_observations_period_basis_check
          CHECK (period_basis IN ('full_year','ytd_q1','ytd_q2','ytd_q3','as_of_date')),
        CONSTRAINT canonical_observations_status_check
          CHECK (status IN ('reported','estimated','revised','final'))
      )
    SQL

    add_index "warehouse.canonical_observations",
              %i[measure_id measurement_year value_type period_basis observed_organization_id geo_boundary_id],
              unique: true,
              name: "idx_canonical_observations_unique"
    add_index "warehouse.canonical_observations", :extracted_observation_id, unique: true,
              name: "idx_canonical_observations_extracted_unique"
    add_index "warehouse.canonical_observations", [ :measure_id, :measurement_year ],
              name: "idx_canonical_observations_measure_year"
    add_index "warehouse.canonical_observations", :document_id,
              name: "idx_canonical_observations_document"
    add_index "warehouse.canonical_observations", :observed_organization_id,
              name: "idx_canonical_observations_observed_org"
    add_index "warehouse.canonical_observations", :jurisdiction_id,
              name: "idx_canonical_observations_jurisdiction"
  end

  def down
    drop_table "warehouse.canonical_observations"
  end
end
