class RequireCompletedFinancialStatementChecks < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :financial_statement_extractions,
      "status NOT IN ('extracted', 'needs_review', 'approved', 'rejected', 'failed') " \
        "OR (jsonb_typeof(check_results) = 'array' AND jsonb_array_length(check_results) > 0)",
      name: "financial_statement_extractions_completed_checks",
      schema: "warehouse", validate: false
    validate_check_constraint :financial_statement_extractions,
      name: "financial_statement_extractions_completed_checks", schema: "warehouse"
  end
end
