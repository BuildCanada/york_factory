class CreateSpendingDeviationsView < ActiveRecord::Migration[8.1]
  def up
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

  def down
    execute "DROP VIEW IF EXISTS spending_deviations;"
  end
end
