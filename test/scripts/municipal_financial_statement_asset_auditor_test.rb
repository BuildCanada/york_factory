# frozen_string_literal: true

require "test_helper"
require Rails.root.join("script/audit_municipal_financial_statement_assets")

class MunicipalFinancialStatementAssetAuditorTest < ActiveSupport::TestCase
  setup do
    @auditor = AuditMunicipalFinancialStatementAssets.allocate
  end

  test "rejects disagreement between the period end and canonical id" do
    document = {
      "canonical_id" => "ca/bc/midway/documents/financial-statements/2026/consolidated",
      "fiscal_period_end" => "2025-12-31"
    }

    error = assert_raises(RuntimeError) { @auditor.send(:document_fiscal_year, document) }
    assert_equal "document canonical and fiscal years disagree: 2026 != 2025", error.message
  end

  test "falls back to the canonical document id" do
    document = {
      "canonical_id" => "ca/bc/midway/documents/financial-statements/2024/consolidated"
    }

    assert_equal 2024, @auditor.send(:document_fiscal_year, document)
  end
end
