class CreateFinancialStatementExtractions < ActiveRecord::Migration[8.1]
  def change
    create_table "warehouse.financial_statement_extractions" do |t|
      t.string :institution_canonical_id, null: false
      t.string :document_canonical_id, null: false
      t.string :asset_sha256, null: false
      t.date :fiscal_year_end, null: false
      t.string :statement_basis, null: false, default: "consolidated"
      t.string :language
      t.string :extractor_version, null: false
      t.string :llm_model
      t.string :status, null: false, default: "pending"
      t.jsonb :check_results, null: false, default: []
      t.jsonb :llm_prompt_snapshot
      t.jsonb :llm_response_snapshot
      t.text :error_message
      t.string :reviewed_by
      t.datetime :reviewed_at
      t.text :review_notes
      t.timestamps

      t.index [ :asset_sha256, :extractor_version ], unique: true,
        name: "index_financial_statement_extractions_source_version"
      t.index [ :institution_canonical_id, :fiscal_year_end ],
        name: "index_financial_statement_extractions_institution_year"
      t.check_constraint "asset_sha256 ~ '^[0-9a-f]{64}$'",
        name: "financial_statement_extractions_sha256"
      t.check_constraint "statement_basis IN ('consolidated','non_consolidated')",
        name: "financial_statement_extractions_basis"
      t.check_constraint "language IS NULL OR language IN ('en','fr','bilingual')",
        name: "financial_statement_extractions_language"
      t.check_constraint "status IN ('pending','extracting','extracted','needs_review','approved','rejected','failed')",
        name: "financial_statement_extractions_status"
      t.check_constraint "(reviewed_at IS NULL) = (reviewed_by IS NULL)",
        name: "financial_statement_extractions_reviewer_pair"
    end

    create_table "warehouse.financial_statement_facts" do |t|
      t.references :financial_statement_extraction, null: false,
        foreign_key: { to_table: "warehouse.financial_statement_extractions" },
        index: { name: "index_financial_statement_facts_on_extraction_id" }
      t.string :concept, null: false
      t.decimal :value, precision: 24, scale: 2, null: false
      t.string :raw_text, null: false
      t.string :raw_label, null: false
      t.integer :scale, null: false, default: 1
      t.string :statement, null: false
      t.integer :source_page, null: false
      t.string :column_year, null: false
      t.decimal :extraction_confidence, precision: 5, scale: 4
      t.timestamps

      t.index [ :financial_statement_extraction_id, :concept ], unique: true,
        name: "index_financial_statement_facts_extraction_concept"
      t.check_constraint <<~SQL.squish,
        concept IN (
          'total_financial_assets','total_liabilities','net_financial_assets',
          'total_non_financial_assets','accumulated_surplus','opening_accumulated_surplus',
          'total_revenue','total_expenses','annual_surplus'
        )
      SQL
        name: "financial_statement_facts_concept"
      t.check_constraint "scale IN (1,1000,1000000)",
        name: "financial_statement_facts_scale"
      t.check_constraint "statement IN ('financial_position','operations','accumulated_surplus')",
        name: "financial_statement_facts_statement"
      t.check_constraint "source_page > 0", name: "financial_statement_facts_source_page"
      t.check_constraint "extraction_confidence IS NULL OR (extraction_confidence >= 0 AND extraction_confidence <= 1)",
        name: "financial_statement_facts_confidence"
    end
  end
end
