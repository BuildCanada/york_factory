class AddYearToFinancialStatementExtractionIdentity < ActiveRecord::Migration[8.1]
  def change
    remove_index "warehouse.financial_statement_extractions",
      name: "index_financial_statement_extractions_source_version"
    add_index "warehouse.financial_statement_extractions",
      [ :institution_release_id, :asset_sha256, :extractor_version, :fiscal_year_end ],
      unique: true, name: "index_financial_statement_extractions_source_version_year"
  end
end
