# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../../script/audit_municipal_ten_year_financial_coverage"

class AuditMunicipalTenYearFinancialCoverageTest < Minitest::Test
  def test_counts_distinct_years_with_valid_local_assets
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      asset = write_asset(root)
      manifest_path = root.join("manifest.json")
      manifest_path.write(JSON.generate(
        "municipalities" => [
          institution("ca/test/nine", (2015..2023), asset),
          institution("ca/test/ten", (2015..2024), asset),
          institution("ca/test/invalid", [ 2024 ], asset.merge("content_sha256" => "0" * 64))
        ]
      ))
      config_path = root.join("config.json")
      config_path.write(JSON.generate(
        "generated_at" => "2026-08-25T00:00:00Z",
        "provinces" => [
          {
            "province" => "test",
            "manifest_path" => manifest_path.to_s,
            "scope_note" => "Test municipalities.",
            "included_statuses" => [ "active" ]
          }
        ]
      ))

      payload = AuditMunicipalTenYearFinancialCoverage.new(
        config_path: config_path,
        output_path: root.join("audit.json"),
        asset_root: root,
        allow_incomplete: true,
        ids_dir: root.join("ids")
      ).run

      province = payload.fetch("provinces").first
      assert_equal 3, province.fetch("scoped_institution_count")
      assert_equal 2, province.fetch("eligible_institution_count")
      assert_equal 1, province.fetch("zero_statement_institution_count")
      assert_equal "ca/test/invalid", province.dig("zero_statement_institutions", 0, "canonical_id")
      assert_equal 1, province.dig("zero_statement_institutions", 0, "financial_statement_document_count")
      assert_equal 3, payload.dig("totals", "scoped_institution_count")
      assert_equal 1, payload.dig("totals", "zero_statement_institution_count")
      assert_equal "test", payload.dig("totals", "zero_statement_institutions", 0, "province")
      assert_equal 1, province.fetch("ten_year_complete_count")
      assert_equal 1, province.fetch("shortfall_institution_count")
      assert_equal 1, province.fetch("missing_year_slot_count")
      assert_equal 1, province.fetch("asset_integrity_error_count")
      assert_equal "ca/test/invalid", province.dig("asset_integrity_errors", 0, "canonical_id")
      assert_equal "ca/test/nine", province.fetch("gaps").first.fetch("canonical_id")
      assert_equal (2015..2023).to_a, province.fetch("gaps").first.fetch("downloaded_years")
      assert_equal "ca/test/nine\n", root.join("ids", "test.txt").read
      assert_equal "2026-08-25T00:00:00Z", payload.fetch("config_generated_at")
      refute_equal payload.fetch("config_generated_at"), payload.fetch("generated_at")
      assert Time.iso8601(payload.fetch("generated_at"))
      refute payload.fetch("all_institutions_pass")
    end
  end

  def test_wrong_asset_root_is_an_integrity_failure_instead_of_an_empty_pass
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      asset = write_asset(root)
      manifest_path = root.join("manifest.json")
      manifest_path.write(JSON.generate(
        "municipalities" => [ institution("ca/test/example", [ 2024 ], asset) ]
      ))
      config_path = root.join("config.json")
      config_path.write(JSON.generate(
        "generated_at" => "2026-08-25T00:00:00Z",
        "provinces" => [
          {
            "province" => "test",
            "manifest_path" => manifest_path.to_s,
            "scope_note" => "Test municipalities."
          }
        ]
      ))

      payload = AuditMunicipalTenYearFinancialCoverage.new(
        config_path: config_path,
        output_path: root.join("audit.json"),
        asset_root: root.join("wrong-root"),
        allow_incomplete: true
      ).run

      province = payload.fetch("provinces").first
      assert_equal 0, province.fetch("eligible_institution_count")
      assert_equal 1, province.fetch("asset_integrity_error_count")
      assert_equal 0.0, province.fetch("ten_year_complete_percent")
      assert_equal 1, payload.dig("totals", "asset_integrity_error_count")
      refute province.fetch("passes")
      refute payload.fetch("all_institutions_pass")
    end
  end

  def test_checks_integrity_of_predecessor_documents_used_for_lineage
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      asset = write_asset(root)
      manifest_path = root.join("manifest.json")
      manifest_path.write(JSON.generate(
        "municipalities" => [
          institution("ca/test/current", [], asset),
          institution("ca/test/predecessor", [ 2024 ], asset).merge("status" => "dissolved")
        ],
        "relationships" => [
          {
            "source_id" => "ca/test/current",
            "target_id" => "ca/test/predecessor",
            "relationship_type" => "succeeds",
            "source_url" => "https://laws.example.test/restructuring"
          }
        ]
      ))
      config_path = root.join("config.json")
      config_path.write(JSON.generate(
        "generated_at" => "2026-08-25T00:00:00Z",
        "provinces" => [
          {
            "province" => "test",
            "manifest_path" => manifest_path.to_s,
            "scope_note" => "Test municipalities.",
            "included_statuses" => [ "active" ]
          }
        ]
      ))

      payload = AuditMunicipalTenYearFinancialCoverage.new(
        config_path: config_path,
        output_path: root.join("audit.json"),
        asset_root: root.join("wrong-root"),
        allow_incomplete: true,
        include_predecessors: true
      ).run
      province = payload.fetch("provinces").first
      assert_equal 1, province.fetch("asset_integrity_error_count")
      assert_equal "ca/test/predecessor", province.dig("asset_integrity_errors", 0, "canonical_id")
      refute province.fetch("passes")
    end
  end

  def test_counts_sourced_predecessor_years_without_reassigning_documents
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      asset = write_asset(root)
      manifest_path = root.join("manifest.json")
      manifest_path.write(JSON.generate(
        "municipalities" => [
          institution("ca/test/current", [ 2024 ], asset),
          institution("ca/test/predecessor", (2015..2023), asset).merge("status" => "dissolved")
        ],
        "relationships" => [
          {
            "source_id" => "ca/test/current",
            "target_id" => "ca/test/predecessor",
            "relationship_type" => "succeeds",
            "valid_from" => "2024-01-01",
            "source_url" => "https://laws.example.test/restructuring"
          }
        ]
      ))
      config_path = root.join("config.json")
      config_path.write(JSON.generate(
        "generated_at" => "2026-08-25T00:00:00Z",
        "provinces" => [
          {
            "province" => "test",
            "manifest_path" => manifest_path.to_s,
            "scope_note" => "Test municipalities.",
            "included_statuses" => [ "active" ]
          }
        ]
      ))

      payload = AuditMunicipalTenYearFinancialCoverage.new(
        config_path: config_path,
        output_path: root.join("audit.json"),
        asset_root: root,
        allow_incomplete: true,
        include_predecessors: true
      ).run

      current = payload.dig("provinces", 0, "gaps").find { _1["canonical_id"] == "ca/test/current" }
      assert_nil current
      assert_equal "issuer_and_sourced_predecessors", payload.fetch("counting_basis")
      assert_equal 1, payload.dig("provinces", 0, "ten_year_complete_count")
      assert_equal 1, payload.dig("provinces", 0, "lineage_assisted_complete_count")
      assert_equal "ca/test/current", payload.dig("provinces", 0, "lineage_assisted_completions", 0, "canonical_id")
      assert_equal 0, payload.dig("provinces", 0, "shortfall_institution_count")
      assert_equal 0, payload.dig("provinces", 0, "lineage_only_institution_count")
    end
  end

  def test_reports_lineage_only_institutions_without_changing_the_eligible_denominator
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      asset = write_asset(root)
      manifest_path = root.join("manifest.json")
      manifest_path.write(JSON.generate(
        "municipalities" => [
          institution("ca/test/current", [], asset),
          institution("ca/test/predecessor", (2015..2024), asset).merge("status" => "dissolved")
        ],
        "relationships" => [
          {
            "source_id" => "ca/test/current",
            "target_id" => "ca/test/predecessor",
            "relationship_type" => "succeeds",
            "source_url" => "https://laws.example.test/restructuring"
          }
        ]
      ))
      config_path = root.join("config.json")
      config_path.write(JSON.generate(
        "generated_at" => "2026-08-25T00:00:00Z",
        "provinces" => [
          {
            "province" => "test",
            "manifest_path" => manifest_path.to_s,
            "scope_note" => "Test municipalities.",
            "included_statuses" => [ "active" ]
          }
        ]
      ))

      payload = AuditMunicipalTenYearFinancialCoverage.new(
        config_path: config_path,
        output_path: root.join("audit.json"),
        asset_root: root,
        allow_incomplete: true,
        include_predecessors: true
      ).run
      issuer_payload = AuditMunicipalTenYearFinancialCoverage.new(
        config_path: config_path,
        output_path: root.join("issuer-audit.json"),
        asset_root: root,
        allow_incomplete: true
      ).run

      province = payload.fetch("provinces").first
      assert_equal 1, province.fetch("scoped_institution_count")
      assert_equal 0, province.fetch("eligible_institution_count")
      assert_equal 1, province.fetch("zero_statement_institution_count")
      assert_equal 1, province.fetch("lineage_only_institution_count")
      assert_equal "ca/test/current", province.dig("lineage_only_institutions", 0, "canonical_id")
      assert_equal 10, province.dig("lineage_only_institutions", 0, "predecessor_downloaded_year_count")
      assert_equal 0, province.fetch("ten_year_complete_count")
      assert_equal 0, province.fetch("lineage_assisted_complete_count")
      assert_equal 1, payload.dig("totals", "lineage_only_institution_count")
      assert_equal issuer_payload.dig("totals", "eligible_institution_count"),
        payload.dig("totals", "eligible_institution_count")
    end
  end

  def test_does_not_count_an_unsourced_predecessor_relationship
    auditor = AuditMunicipalTenYearFinancialCoverage.allocate
    graph = auditor.send(
      :predecessor_graph,
      "relationships" => [
        {
          "source_id" => "ca/test/current",
          "target_id" => "ca/test/predecessor",
          "relationship_type" => "succeeds"
        }
      ]
    )

    assert_empty graph["ca/test/current"]
  end

  def test_reports_a_document_whose_canonical_and_fiscal_years_disagree_as_an_integrity_error
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      asset = write_asset(root)
      row = institution("ca/test/example", [ 2025 ], asset)
      row.fetch("documents").first["fiscal_period_end"] = "2024-12-31"
      manifest_path = root.join("manifest.json")
      manifest_path.write(JSON.generate("municipalities" => [ row ]))
      config_path = root.join("config.json")
      config_path.write(JSON.generate(
        "generated_at" => "2026-08-25T00:00:00Z",
        "provinces" => [
          {
            "province" => "test",
            "manifest_path" => manifest_path.to_s,
            "scope_note" => "Test municipalities."
          }
        ]
      ))

      payload = AuditMunicipalTenYearFinancialCoverage.new(
        config_path: config_path,
        output_path: root.join("audit.json"),
        asset_root: root,
        allow_incomplete: true
      ).run

      province = payload.fetch("provinces").first
      assert_equal 0, province.fetch("eligible_institution_count")
      assert_equal 1, province.fetch("zero_statement_institution_count")
      assert_equal 1, province.fetch("asset_integrity_error_count")
      error = province.fetch("asset_integrity_errors").first
      assert_equal "canonical ID year disagrees with fiscal_period_end year", error.fetch("reason")
      assert_equal 2025, error.fetch("canonical_id_year")
      assert_equal 2024, error.fetch("fiscal_period_end_year")
      refute province.fetch("passes")
    end
  end

  private

  def write_asset(root)
    bytes = "%PDF-1.4\nvalid test payload\n"
    digest = Digest::SHA256.hexdigest(bytes)
    path = root.join("sha256", digest[0, 2], "#{digest}.pdf")
    path.dirname.mkpath
    path.binwrite(bytes)
    {
      "archive_path" => path.relative_path_from(root).to_s,
      "content_sha256" => digest,
      "byte_size" => bytes.bytesize
    }
  end

  def institution(canonical_id, years, asset)
    {
      "canonical_id" => canonical_id,
      "official_name" => canonical_id,
      "website_url" => "https://example.test",
      "documents" => years.map do |year|
        {
          "canonical_id" => "#{canonical_id}/documents/financial-statements/#{year}/general",
          "document_type" => "financial-statements",
          "assets" => [ asset ]
        }
      end
    }
  end
end
