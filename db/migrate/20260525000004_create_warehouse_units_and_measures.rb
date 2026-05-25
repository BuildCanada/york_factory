class CreateWarehouseUnitsAndMeasures < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE warehouse.units (
        id bigserial PRIMARY KEY,
        symbol varchar NOT NULL UNIQUE,
        kind varchar NOT NULL,
        base_unit varchar,
        scale double precision NOT NULL DEFAULT 1.0,
        currency_code varchar,
        denominator_unit varchar,
        denominator_scale double precision,
        notes text,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL,
        CONSTRAINT units_kind_check
          CHECK (kind IN ('absolute','ratio','rate','qualitative')),
        CONSTRAINT units_base_unit_check
          CHECK (base_unit IS NULL OR base_unit IN
            ('ratio','count','dollars','seconds','minutes','hours','days',
             'meters','kilometers','square_meters','hectares','tonnes',
             'kwh','mwh','tco2e','other')),
        CONSTRAINT units_qualitative_has_no_base
          CHECK ((kind = 'qualitative') = (base_unit IS NULL)),
        CONSTRAINT units_rate_has_denominator
          CHECK ((kind = 'rate') = (denominator_unit IS NOT NULL))
      )
    SQL

    execute <<~SQL
      CREATE TABLE warehouse.measures (
        id bigserial PRIMARY KEY,
        organization_id bigint REFERENCES warehouse.organizations(id),
        slug varchar NOT NULL,
        canonical_name varchar NOT NULL,
        unit_id bigint NOT NULL REFERENCES warehouse.units(id),
        service_category varchar,
        description text,
        first_seen_year integer,
        last_seen_year integer,
        created_at timestamp(6) NOT NULL,
        updated_at timestamp(6) NOT NULL
      )
    SQL

    # NULL organization_id means cross-agency. Postgres treats NULLs as distinct in
    # a regular UNIQUE constraint, so we use a partial index pair for both branches.
    add_index "warehouse.measures", [ :organization_id, :slug ], unique: true,
              where: "organization_id IS NOT NULL",
              name: "idx_measures_org_slug_unique"
    add_index "warehouse.measures", :slug, unique: true,
              where: "organization_id IS NULL",
              name: "idx_measures_cross_agency_slug_unique"
    add_index "warehouse.measures", :organization_id
    add_index "warehouse.measures", :unit_id
  end

  def down
    drop_table "warehouse.measures"
    drop_table "warehouse.units"
  end
end
