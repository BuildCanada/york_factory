# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../script/promote_embedded_municipal_financial_statements"

class PromoteEmbeddedMunicipalFinancialStatementsTest < Minitest::Test
  def setup
    @promoter = PromoteEmbeddedMunicipalFinancialStatements.allocate
  end

  def test_existing_financial_statement_keys_include_each_archived_year_and_content_hash
    row = {
      "documents" => [
        {
          "document_type" => "financial-statements",
          "year" => 2024,
          "assets" => [ { "content_sha256" => "a" }, { "content_sha256" => "b" } ]
        },
        {
          "document_type" => "annual-report",
          "year" => 2023,
          "assets" => [ { "content_sha256" => "c" } ]
        }
      ]
    }

    keys = @promoter.send(:existing_financial_statement_keys, row)

    assert keys.include?([ 2024, "a" ])
    assert keys.include?([ 2024, "b" ])
    refute keys.include?([ 2023, "c" ])
  end

  def test_existing_financial_statement_keys_derive_year_from_canonical_id
    row = {
      "documents" => [
        {
          "canonical_id" => "ca/on/example/documents/financial-statements/2024/general",
          "document_type" => "financial-statements",
          "assets" => [ { "content_sha256" => "a" } ]
        }
      ]
    }

    keys = @promoter.send(:existing_financial_statement_keys, row)

    assert keys.include?([ 2024, "a" ])
  end

  def test_official_name_prefers_unilingual_canonical_name_before_french_fallback
    row = {
      "official_name_en" => nil,
      "official_name" => "Municipality of the District of Argyle",
      "official_name_fr" => "Municipalite du district d'Argyle"
    }

    assert_equal "Municipality of the District of Argyle", @promoter.send(:official_name, row)
  end
end
