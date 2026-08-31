# Run after the public-institution ontology deploy and before deploying the
# stacked municipal financial-statements PR.
connection = Warehouse::FinancialStatementExtraction.connection
table = "warehouse.financial_statement_extractions"
abort "#{table} does not exist; deploy the parent ontology PR first" unless connection.data_source_exists?(table)

terminal = %w[extracted needs_review approved rejected failed]
scope = Warehouse::FinancialStatementExtraction.where(status: terminal)
missing_checks = scope.where(<<~SQL.squish).count
  check_results IS NULL
  OR jsonb_typeof(check_results) <> 'array'
  OR jsonb_array_length(check_results) = 0
SQL
approved_without_review = Warehouse::FinancialStatementExtraction.where(status: "approved")
  .where("reviewed_at IS NULL OR reviewed_by IS NULL").count
unpaired_review = Warehouse::FinancialStatementExtraction
  .where("(reviewed_at IS NULL) <> (reviewed_by IS NULL)").count

result = {
  table:,
  terminal_rows: scope.count,
  terminal_without_checks: missing_checks,
  approved_without_review:,
  unpaired_review:,
  ready: missing_checks.zero? && approved_without_review.zero? && unpaired_review.zero?
}
puts result.to_json
abort "municipal financial migration preflight failed" unless result.fetch(:ready)
