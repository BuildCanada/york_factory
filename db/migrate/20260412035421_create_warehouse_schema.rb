class CreateWarehouseSchema < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE SCHEMA IF NOT EXISTS warehouse"

    %w[
      sources
      raw_ingestions
      lineage_entries
      organizations
      organization_aliases
      fiscal_authorities
      fiscal_expenditures
      standard_object_expenditures
      lobbying_activities
      lobbyists
    ].each do |table|
      execute "ALTER TABLE #{table} SET SCHEMA warehouse"
    end

    execute "DROP VIEW IF EXISTS spending_deviations"

    execute <<~SQL
      CREATE VIEW warehouse.spending_deviations AS
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
      FROM warehouse.fiscal_authorities fa
      LEFT JOIN warehouse.fiscal_expenditures fe
        ON fa.organization_id = fe.organization_id
        AND fa.fiscal_year = fe.fiscal_year
        AND fa.vote_number = fe.vote_number
      GROUP BY fa.organization_id, fa.fiscal_year, fa.vote_number, fa.vote_type,
               fe.actual_expenditure
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS warehouse.spending_deviations"

    %w[
      sources
      raw_ingestions
      lineage_entries
      organizations
      organization_aliases
      fiscal_authorities
      fiscal_expenditures
      standard_object_expenditures
      lobbying_activities
      lobbyists
    ].each do |table|
      execute "ALTER TABLE warehouse.#{table} SET SCHEMA public"
    end

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
               fe.actual_expenditure
    SQL

    execute "DROP SCHEMA IF EXISTS warehouse"
  end
end
