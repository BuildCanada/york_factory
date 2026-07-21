class AddQuarterPeriodBasis < ActiveRecord::Migration[8.1]
  # Quarterly series (StatCan FDI flows, gross fixed capital formation,
  # debt-to-GDP ratios) store four rows per (measure, year, jurisdiction),
  # differentiated by period_start — which the unique index already includes
  # (added for monthly CPI). Only the period_basis check constraints need to
  # learn the new "quarter" value.
  PERIOD_BASES_WITH_QUARTER = %w[full_year ytd_q1 ytd_q2 ytd_q3 as_of_date month quarter].freeze
  PERIOD_BASES_WITHOUT_QUARTER = PERIOD_BASES_WITH_QUARTER - %w[quarter]

  def up
    replace_period_basis_checks(PERIOD_BASES_WITH_QUARTER)
  end

  def down
    replace_period_basis_checks(PERIOD_BASES_WITHOUT_QUARTER)
  end

  private

  def replace_period_basis_checks(allowed_values)
    values_sql = allowed_values.map { |v| "'#{v}'::character varying" }.join(", ")

    {
      "warehouse.extracted_observations" => "extracted_observations_period_basis_check",
      "warehouse.canonical_observations" => "canonical_observations_period_basis_check"
    }.each do |table, constraint|
      remove_check_constraint table, name: constraint, if_exists: true
      add_check_constraint table,
        "period_basis::text = ANY (ARRAY[#{values_sql}]::text[])",
        name: constraint
    end
  end
end
