class AddKpiFieldsToOrganizations < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE warehouse.organizations
        ADD COLUMN jurisdiction_id bigint,
        ADD COLUMN slug varchar,
        ADD COLUMN kind varchar,
        ADD COLUMN parent_organization_id bigint,
        ADD COLUMN active_from_year integer,
        ADD COLUMN active_to_year integer,
        ADD COLUMN description text
    SQL

    # Backfill jurisdiction_id for existing rows (all federal — pipeline pre-dated multi-jurisdiction).
    execute <<~SQL
      UPDATE warehouse.organizations
      SET jurisdiction_id = (SELECT id FROM warehouse.jurisdictions WHERE code = 'CA' LIMIT 1)
      WHERE jurisdiction_id IS NULL
    SQL

    # Backfill slug from canonical_name for existing rows.
    execute <<~SQL
      UPDATE warehouse.organizations
      SET slug = regexp_replace(
        regexp_replace(lower(unaccent(canonical_name)), '[^a-z0-9]+', '-', 'g'),
        '(^-+|-+$)', '', 'g'
      )
      WHERE slug IS NULL
    SQL

    execute <<~SQL
      ALTER TABLE warehouse.organizations
        ALTER COLUMN jurisdiction_id SET NOT NULL,
        ALTER COLUMN slug SET NOT NULL,
        ADD CONSTRAINT fk_organizations_jurisdiction
          FOREIGN KEY (jurisdiction_id) REFERENCES warehouse.jurisdictions(id),
        ADD CONSTRAINT fk_organizations_parent
          FOREIGN KEY (parent_organization_id) REFERENCES warehouse.organizations(id)
    SQL

    add_index "warehouse.organizations", [ :jurisdiction_id, :slug ], unique: true,
              name: "idx_organizations_jurisdiction_slug"
    add_index "warehouse.organizations", :jurisdiction_id
    add_index "warehouse.organizations", :parent_organization_id
  end

  def down
    execute <<~SQL
      ALTER TABLE warehouse.organizations
        DROP CONSTRAINT IF EXISTS fk_organizations_parent,
        DROP CONSTRAINT IF EXISTS fk_organizations_jurisdiction,
        DROP COLUMN description,
        DROP COLUMN active_to_year,
        DROP COLUMN active_from_year,
        DROP COLUMN parent_organization_id,
        DROP COLUMN kind,
        DROP COLUMN slug,
        DROP COLUMN jurisdiction_id
    SQL
  end
end
