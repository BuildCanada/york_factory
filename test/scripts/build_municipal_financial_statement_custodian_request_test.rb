# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../script/build_municipal_financial_statement_custodian_request"

class BuildMunicipalFinancialStatementCustodianRequestTest < Minitest::Test
  def test_splits_requested_years_between_successor_and_legal_predecessor
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "manifest.json")
      gaps = File.join(dir, "gaps.txt")
      output = File.join(dir, "output")
      File.write(manifest, JSON.generate(synthetic_manifest))
      File.write(gaps, "ca/nb/new-town\n")

      summary = BuildMunicipalFinancialStatementCustodianRequest.new(
        manifest: manifest, gap_ids: gaps, province: "nb", output_dir: output
      ).call
      rows = JSON.parse(File.read(File.join(output, "gap-inventory.json"))).fetch("request_rows")
      current = rows.find { _1["relationship_to_subject"] == "self" }
      predecessor = rows.find { _1["relationship_to_subject"] == "predecessor" }

      assert_equal [ 2024, 2025 ], current.fetch("requested_fiscal_years")
      assert_equal (2016..2021).to_a, predecessor.fetch("requested_fiscal_years")
      assert_equal "ca/nb/old-town", predecessor.fetch("issuer_canonical_id")
      assert_equal 8, summary.fetch(:requested_issuer_year_count)
      assert_includes File.read(File.join(output, "request-draft.md")), "DRAFT — NOT SENT"
    end
  end

  def test_supports_saskatchewan_as_a_custodian
    Dir.mktmpdir do |dir|
      manifest = File.join(dir, "manifest.json")
      gaps = File.join(dir, "gaps.txt")
      output = File.join(dir, "output")
      File.write(manifest, JSON.generate(synthetic_manifest))
      File.write(gaps, "ca/nb/new-town\n")

      summary = BuildMunicipalFinancialStatementCustodianRequest.new(
        manifest: manifest, gap_ids: gaps, province: "sk", output_dir: output
      ).call
      draft = File.read(File.join(output, "request-draft.md"))

      assert_equal "sk", summary.fetch(:province)
      assert_includes draft, "Ministry of Government Relations"
      assert_includes draft, "DRAFT — NOT SENT"
    end
  end

  private

  def synthetic_manifest
    {
      "municipalities" => [
        {
          "canonical_id" => "ca/nb/new-town",
          "official_name_en" => "New Town",
          "documents" => [ financial_document("ca/nb/new-town", 2023) ]
        },
        {
          "canonical_id" => "ca/nb/old-town",
          "official_name_en" => "Old Town",
          "documents" => [ financial_document("ca/nb/old-town", 2022) ]
        }
      ],
      "relationships" => [
        {
          "source_id" => "ca/nb/new-town",
          "target_id" => "ca/nb/old-town",
          "relationship_type" => "succeeds",
          "valid_from" => "2023-01-01"
        }
      ]
    }
  end

  def financial_document(id, year)
    {
      "canonical_id" => "#{id}/documents/financial-statements/#{year}/general",
      "document_type" => "financial-statements",
      "assets" => [ { "content_sha256" => "b" * 64 } ]
    }
  end
end
