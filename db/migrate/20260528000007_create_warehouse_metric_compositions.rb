class CreateWarehouseMetricCompositions < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.metric_compositions (
        id bigserial PRIMARY KEY,
        measure_id bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        composition_type varchar NOT NULL,
        name             varchar NOT NULL,
        expected_total          numeric,
        expected_total_unit_id  bigint REFERENCES warehouse.units(id),
        allow_other   boolean NOT NULL DEFAULT true,
        allow_unknown boolean NOT NULL DEFAULT true,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.metric_compositions", [ :measure_id, :composition_type ], unique: true,
              name: "idx_metric_compositions_measure_type"

    execute <<~SQL
      CREATE TABLE warehouse.metric_components (
        id bigserial PRIMARY KEY,
        measure_id     bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        composition_id bigint REFERENCES warehouse.metric_compositions(id) ON DELETE CASCADE,
        component_type varchar NOT NULL,
        component_code varchar,
        component_name varchar NOT NULL,
        parent_component_id bigint REFERENCES warehouse.metric_components(id),
        valid_from date,
        valid_to   date,
        sort_order integer,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    add_index "warehouse.metric_components", [ :measure_id, :component_type, :component_code ], unique: true,
              where: "component_code IS NOT NULL",
              name: "idx_metric_components_measure_type_code"
    add_index "warehouse.metric_components", :composition_id, name: "idx_metric_components_composition"
    add_index "warehouse.metric_components", :parent_component_id, name: "idx_metric_components_parent"

    execute <<~SQL
      CREATE TABLE warehouse.metric_component_relationships (
        id bigserial PRIMARY KEY,
        from_component_id bigint NOT NULL REFERENCES warehouse.metric_components(id) ON DELETE CASCADE,
        to_component_id   bigint NOT NULL REFERENCES warehouse.metric_components(id) ON DELETE CASCADE,
        relationship_type varchar NOT NULL,
        valid_from date,
        valid_to   date,
        source_id  bigint REFERENCES warehouse.sources(id),
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT mcr_distinct CHECK (from_component_id <> to_component_id),
        CONSTRAINT mcr_relationship_kind_check
          CHECK (relationship_type IN
            ('renamed_to','split_into','merged_into','reclassified_as',
             'equivalent_to','parent_of','child_of'))
      )
    SQL

    add_index "warehouse.metric_component_relationships",
              [ :from_component_id, :to_component_id, :relationship_type ], unique: true,
              name: "idx_mcr_unique"

    execute <<~SQL
      CREATE TABLE warehouse.composition_validation_results (
        id bigserial PRIMARY KEY,
        measure_id     bigint NOT NULL REFERENCES warehouse.measures(id) ON DELETE CASCADE,
        composition_id bigint NOT NULL REFERENCES warehouse.metric_compositions(id) ON DELETE CASCADE,
        observed_organization_id bigint REFERENCES warehouse.organizations(id),
        geo_boundary_id bigint REFERENCES warehouse.geo_boundaries(id),
        period_start date,
        period_end   date,
        measurement_year integer,
        validation_type varchar NOT NULL,
        status varchar NOT NULL,
        expected_value numeric,
        actual_value   numeric,
        difference     numeric,
        severity varchar,
        message  text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT cvr_status_check
          CHECK (status IN ('ok','warn','fail')),
        CONSTRAINT cvr_severity_check
          CHECK (severity IS NULL OR severity IN ('low','medium','high','critical'))
      )
    SQL

    add_index "warehouse.composition_validation_results", :composition_id,
              name: "idx_cvr_composition"
    add_index "warehouse.composition_validation_results", :measurement_year,
              name: "idx_cvr_year"
    add_index "warehouse.composition_validation_results", :status,
              name: "idx_cvr_status"

    # Composition / component refs on observations.
    execute "ALTER TABLE warehouse.extracted_observations ADD COLUMN composition_id bigint REFERENCES warehouse.metric_compositions(id)"
    execute "ALTER TABLE warehouse.extracted_observations ADD COLUMN component_id   bigint REFERENCES warehouse.metric_components(id)"
    execute "ALTER TABLE warehouse.canonical_observations ADD COLUMN composition_id bigint REFERENCES warehouse.metric_compositions(id)"
    execute "ALTER TABLE warehouse.canonical_observations ADD COLUMN component_id   bigint REFERENCES warehouse.metric_components(id)"
    add_index "warehouse.extracted_observations", :composition_id, name: "idx_extracted_observations_composition"
    add_index "warehouse.extracted_observations", :component_id,   name: "idx_extracted_observations_component"
    add_index "warehouse.canonical_observations", :composition_id, name: "idx_canonical_observations_composition"
    add_index "warehouse.canonical_observations", :component_id,   name: "idx_canonical_observations_component"
  end

  def down
    %w[component_id composition_id].each do |c|
      execute "ALTER TABLE warehouse.canonical_observations DROP COLUMN IF EXISTS #{c}"
      execute "ALTER TABLE warehouse.extracted_observations DROP COLUMN IF EXISTS #{c}"
    end
    drop_table "warehouse.composition_validation_results"
    drop_table "warehouse.metric_component_relationships"
    drop_table "warehouse.metric_components"
    drop_table "warehouse.metric_compositions"
  end
end
