# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../script/augment_bc_regional_districts"

class BcRegionalDistrictAugmenterTest < Minitest::Test
  def setup
    @augmenter = BcRegionalDistrictAugmenter.allocate
  end

  def test_moves_the_shishalh_government_district_to_the_bc_namespace_without_deleting_geography
    row = {
      "canonical_id" => BcRegionalDistrictAugmenter::SHISHALH_OLD_ID,
      "government_level" => "first_nation",
      "identifiers" => [
        { "scheme" => "civicinfo.bc.organization", "value" => "178" },
        { "scheme" => "statcan.csd", "value" => "5927806" }
      ],
      "statcan_csd_uids" => [ "5927806" ],
      "statcan_geographies" => [ { "uid" => "5927806", "name" => "Sechelt (Part)" } ]
    }

    @augmenter.send(:transform_existing_rows!, [ row ])

    assert_equal BcRegionalDistrictAugmenter::SHISHALH_NEW_ID, row.fetch("canonical_id")
    assert_equal "municipal", row.fetch("government_level")
    assert_equal [ "civicinfo.bc.organization" ], row.fetch("identifiers").map { |identifier| identifier.fetch("scheme") }
    refute row.key?("statcan_csd_uids")
    assert_equal "csd", row.dig("statcan_geographies", 0, "boundary_type")
    assert_equal "governs", row.dig("statcan_geographies", 0, "role")
  end

  def test_builds_semantic_regional_district_ids_and_keeps_islands_trust_distinct
    @augmenter.instance_variable_set(:@retrieved_at, Time.utc(2026, 8, 21))
    regional = @augmenter.send(:regional_row, "Capital", "Regional District", "152", "625 Fisgard", "250-360-3000", "info@example.ca", "https://www.crd.ca")
    trust = @augmenter.send(:regional_row, "Islands Trust", "Islands Trust", "177", "1627 Fort", "250-405-5151", nil, "https://islandstrust.bc.ca")

    assert_equal "ca/bc/capital-regional-district", regional.fetch("canonical_id")
    assert_equal "government", regional.fetch("institution_type")
    assert_equal "regional_district", regional.fetch("jurisdiction_kind")
    assert_equal "ca/bc/islands-trust", trust.fetch("canonical_id")
    assert_equal "government", trust.fetch("institution_type")
    assert_equal "islands_trust", trust.fetch("jurisdiction_kind")
  end

  def test_normalization_preserves_census_division_geographies
    row = {
      "canonical_id" => "ca/bc/capital-regional-district",
      "institution_type" => "regional_district",
      "statcan_geographies" => [
        { "uid" => "5917", "boundary_type" => "cd" },
        { "uid" => "5917034", "boundary_type" => "csd" }
      ]
    }

    @augmenter.send(:normalize_emitted_institution!, row)

    assert_equal %w[cd csd], row.fetch("statcan_geographies").map { |geography| geography.fetch("boundary_type") }
  end

  def test_emits_sofi_as_a_document_type_separate_from_audited_statements
    report_row = {
      "financial_statements" => [ report("financial-statements", "hash-fin") ],
      "annual_reports" => [],
      "sofi_documents" => [ report("statement-of-financial-information", "hash-sofi") ]
    }

    documents = @augmenter.send(:release_documents, report_row)

    assert_equal [ "financial-statements", "statement-of-financial-information" ], documents.map { |document| document.fetch("document_type") }.sort
    assert_equal 2, documents.map { |document| document.fetch("canonical_id") }.uniq.length
  end

  private

  def report(type, hash)
    {
      "canonical_id" => "ca/bc/example-regional-district",
      "title" => "Example 2024",
      "document_type" => type,
      "document_variant" => "general",
      "fiscal_period_start" => "2024-01-01",
      "fiscal_period_end" => "2024-12-31",
      "source_page_url" => "https://example.ca/reports",
      "download_url" => "https://example.ca/#{type}.pdf",
      "retrieved_at" => "2026-08-21T00:00:00Z",
      "archive_path" => "sha256/aa/#{hash}.pdf",
      "content_sha256" => hash,
      "mime_type" => "application/pdf",
      "byte_size" => 42,
      "rights_status" => "metadata_only"
    }
  end
end
