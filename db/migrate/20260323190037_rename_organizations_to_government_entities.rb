class RenameOrganizationsToGovernmentEntities < ActiveRecord::Migration[8.1]
  def up
    # Drop the VIEW first (it references organization_id columns)
    execute "DROP VIEW IF EXISTS spending_deviations;"

    # Rename tables
    rename_table :organizations, :government_entities
    rename_table :organization_aliases, :government_entity_aliases

    # Rename FK columns
    rename_column :government_entity_aliases, :organization_id, :government_entity_id
    rename_column :fiscal_authorities, :organization_id, :government_entity_id
    rename_column :fiscal_expenditures, :organization_id, :government_entity_id
    rename_column :standard_object_expenditures, :organization_id, :government_entity_id
    rename_column :lobbying_activities, :organization_id, :government_entity_id

    # Recreate the VIEW with new column names
    execute <<~SQL
      CREATE VIEW spending_deviations AS
      SELECT
        fa.government_entity_id,
        fa.fiscal_year,
        fa.vote_number,
        fa.vote_type,
        SUM(fa.amount) AS consolidated_estimate,
        fe.actual_expenditure,
        (fe.actual_expenditure - SUM(fa.amount)) AS variance_amount,
        CASE
          WHEN SUM(fa.amount) = 0 THEN NULL
          ELSE ROUND(((fe.actual_expenditure - SUM(fa.amount)) / ABS(SUM(fa.amount))) * 100, 2)
        END AS variance_pct
      FROM fiscal_authorities fa
      LEFT JOIN fiscal_expenditures fe
        ON fa.government_entity_id = fe.government_entity_id
        AND fa.fiscal_year = fe.fiscal_year
        AND fa.vote_number = fe.vote_number
      GROUP BY fa.government_entity_id, fa.fiscal_year, fa.vote_number, fa.vote_type,
               fe.actual_expenditure;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS spending_deviations;"

    rename_column :lobbying_activities, :government_entity_id, :organization_id
    rename_column :standard_object_expenditures, :government_entity_id, :organization_id
    rename_column :fiscal_expenditures, :government_entity_id, :organization_id
    rename_column :fiscal_authorities, :government_entity_id, :organization_id
    rename_column :government_entity_aliases, :government_entity_id, :organization_id

    rename_table :government_entity_aliases, :organization_aliases
    rename_table :government_entities, :organizations

    execute <<~SQL
      CREATE VIEW spending_deviations AS
      SELECT
        fa.organization_id,
        fa.fiscal_year,
        fa.vote_number,
        fa.vote_type,
        SUM(fa.amount) AS consolidated_estimate,
        fe.actual_expenditure,
        (fe.actual_expenditure - SUM(fa.amount)) AS variance_amount,
        CASE
          WHEN SUM(fa.amount) = 0 THEN NULL
          ELSE ROUND(((fe.actual_expenditure - SUM(fa.amount)) / ABS(SUM(fa.amount))) * 100, 2)
        END AS variance_pct
      FROM fiscal_authorities fa
      LEFT JOIN fiscal_expenditures fe
        ON fa.organization_id = fe.organization_id
        AND fa.fiscal_year = fe.fiscal_year
        AND fa.vote_number = fe.vote_number
      GROUP BY fa.organization_id, fa.fiscal_year, fa.vote_number, fa.vote_type,
               fe.actual_expenditure;
    SQL
  end
end
