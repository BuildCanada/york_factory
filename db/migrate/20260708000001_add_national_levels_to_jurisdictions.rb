class AddNationalLevelsToJurisdictions < ActiveRecord::Migration[8.1]
  # G7/OECD comparator countries for the economic dashboards are stored as
  # jurisdictions: `national` for foreign countries (USA, JPN, ...), and
  # `supranational` for aggregates (OECD average, computed G7 average).
  def up
    execute "ALTER TABLE warehouse.jurisdictions DROP CONSTRAINT jurisdictions_level_check"
    execute <<~SQL
      ALTER TABLE warehouse.jurisdictions
        ADD CONSTRAINT jurisdictions_level_check
        CHECK ((level)::text = ANY (ARRAY[
          'municipal', 'regional', 'provincial', 'territorial', 'federal',
          'crown_corp', 'authority', 'national', 'supranational'
        ]::text[]))
    SQL
  end

  def down
    execute "DELETE FROM warehouse.jurisdictions WHERE level IN ('national', 'supranational')"
    execute "ALTER TABLE warehouse.jurisdictions DROP CONSTRAINT jurisdictions_level_check"
    execute <<~SQL
      ALTER TABLE warehouse.jurisdictions
        ADD CONSTRAINT jurisdictions_level_check
        CHECK ((level)::text = ANY (ARRAY[
          'municipal', 'regional', 'provincial', 'territorial', 'federal',
          'crown_corp', 'authority'
        ]::text[]))
    SQL
  end
end
