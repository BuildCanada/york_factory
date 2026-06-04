class AddKpiFieldsToJurisdictions < ActiveRecord::Migration[8.1]
  def up
    enable_extension "unaccent"

    execute <<~SQL
      ALTER TABLE warehouse.jurisdictions
        ADD COLUMN slug varchar,
        ADD COLUMN fiscal_year_start_month integer,
        ADD COLUMN default_currency varchar NOT NULL DEFAULT 'CAD',
        ADD COLUMN region_code varchar
    SQL

    execute <<~SQL
      UPDATE warehouse.jurisdictions
      SET slug = lower(code),
          fiscal_year_start_month = CASE
            WHEN level = 'municipal' THEN 1
            ELSE 4
          END
    SQL

    execute <<~SQL
      ALTER TABLE warehouse.jurisdictions
        ALTER COLUMN slug SET NOT NULL,
        ALTER COLUMN fiscal_year_start_month SET NOT NULL,
        ADD CONSTRAINT jurisdictions_fiscal_year_start_month_check
          CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
        ADD CONSTRAINT jurisdictions_level_check
          CHECK (level IN ('municipal','regional','provincial','territorial','federal','crown_corp','authority'))
    SQL

    add_index "warehouse.jurisdictions", :slug, unique: true
  end

  def down
    execute <<~SQL
      ALTER TABLE warehouse.jurisdictions
        DROP CONSTRAINT IF EXISTS jurisdictions_level_check,
        DROP CONSTRAINT IF EXISTS jurisdictions_fiscal_year_start_month_check,
        DROP COLUMN region_code,
        DROP COLUMN default_currency,
        DROP COLUMN fiscal_year_start_month,
        DROP COLUMN slug
    SQL
  end
end
