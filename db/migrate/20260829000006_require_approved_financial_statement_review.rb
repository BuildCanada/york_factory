class RequireApprovedFinancialStatementReview < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :financial_statement_extractions,
      "status <> 'approved' OR (reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)",
      name: "financial_statement_extractions_approved_review",
      schema: "warehouse"
  end
end
