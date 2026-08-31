# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../script/validate_public_institution_manifest"

class ValidatePublicInstitutionManifestTest < Minitest::Test
  def test_rejects_invalid_relationship_endpoints_types_and_cycles
    validator = ValidatePublicInstitutionManifest.allocate
    validator.instance_variable_set(:@errors, [])
    payload = {
      "municipalities" => [
        { "canonical_id" => "ca/test/a" },
        { "canonical_id" => "ca/test/b" }
      ],
      "relationships" => [
        relationship("ca/test/a", "ca/test/b", primary: true),
        relationship("ca/test/b", "ca/test/a", primary: true),
        { "source_id" => "ca/test/missing", "target_id" => "ca/test/a", "relationship_type" => "invalid" }
      ]
    }

    validator.send(:validate_relationships, payload)
    errors = validator.instance_variable_get(:@errors)
    assert errors.any? { _1.include?("source is missing") }
    assert errors.any? { _1.include?("unsupported relationship type") }
    assert errors.any? { _1.include?("cycle") }
  end

  def test_accepts_a_sourced_successor_edge
    validator = ValidatePublicInstitutionManifest.allocate
    validator.instance_variable_set(:@errors, [])
    payload = {
      "municipalities" => [
        { "canonical_id" => "ca/test/current" },
        { "canonical_id" => "ca/test/predecessor" }
      ],
      "relationships" => [
        {
          "source_id" => "ca/test/current",
          "target_id" => "ca/test/predecessor",
          "relationship_type" => "succeeds",
          "valid_from" => "2023-01-01"
        }
      ]
    }

    validator.send(:validate_relationships, payload)
    assert_empty validator.instance_variable_get(:@errors)
  end

  def test_accepts_declared_province_as_a_relationship_target
    validator = ValidatePublicInstitutionManifest.allocate
    validator.instance_variable_set(:@errors, [])
    payload = {
      "province" => { "code" => "ab" },
      "municipalities" => [ { "canonical_id" => "ca/ab/special-areas-board" } ],
      "relationships" => [
        {
          "source_id" => "ca/ab/special-areas-board",
          "target_id" => "ca/ab",
          "relationship_type" => "controlled_by",
          "ownership_basis" => "statutory",
          "source_url" => "https://www.alberta.ca/special-areas-board"
        }
      ]
    }

    validator.send(:validate_relationships, payload)
    assert_empty validator.instance_variable_get(:@errors)
  end

  def test_rejects_an_undeclared_province_as_a_relationship_target
    validator = ValidatePublicInstitutionManifest.allocate
    validator.instance_variable_set(:@errors, [])
    payload = {
      "province" => { "code" => "ab" },
      "municipalities" => [ { "canonical_id" => "ca/ab/board" } ],
      "relationships" => [
        {
          "source_id" => "ca/ab/board",
          "target_id" => "ca/bc",
          "relationship_type" => "controlled_by"
        }
      ]
    }

    validator.send(:validate_relationships, payload)
    assert_includes validator.instance_variable_get(:@errors), "relationship target is missing: ca/bc"
  end

  def test_rejects_province_root_when_jurisdiction_institution_is_excluded
    validator = ValidatePublicInstitutionManifest.allocate
    validator.instance_variable_set(:@errors, [])
    payload = {
      "province" => { "code" => "ab" },
      "include_jurisdiction_institution" => false,
      "municipalities" => [ { "canonical_id" => "ca/ab/board" } ],
      "relationships" => [
        {
          "source_id" => "ca/ab/board",
          "target_id" => "ca/ab",
          "relationship_type" => "controlled_by"
        }
      ]
    }

    validator.send(:validate_relationships, payload)
    assert_includes validator.instance_variable_get(:@errors), "relationship target is missing: ca/ab"
  end

  def test_warns_deterministically_about_asset_content_shared_across_institutions
    validator = validator_with_diagnostics
    shared_sha256 = "a" * 64
    payload = [
      institution("ca/test/zeta", "ca/test/zeta/documents/report-z", shared_sha256),
      institution("ca/test/alpha", "ca/test/alpha/documents/report-b", shared_sha256),
      institution("ca/test/alpha", "ca/test/alpha/documents/report-a", shared_sha256)
    ]

    validator.send(:validate_cross_institution_duplicate_assets, payload)

    expected = "duplicate asset content_sha256 #{shared_sha256} across institutions " \
      "ca/test/alpha, ca/test/zeta; documents ca/test/alpha/documents/report-a, " \
      "ca/test/alpha/documents/report-b, ca/test/zeta/documents/report-z"
    assert_equal [ expected ], validator.instance_variable_get(:@warnings)
    assert_empty validator.instance_variable_get(:@errors)
  end

  def test_does_not_warn_about_asset_content_reused_within_one_institution
    validator = validator_with_diagnostics
    sha256 = "b" * 64
    payload = [
      institution("ca/test/alpha", "ca/test/alpha/documents/report-a", sha256),
      institution("ca/test/alpha", "ca/test/alpha/documents/report-b", sha256)
    ]

    validator.send(:validate_cross_institution_duplicate_assets, payload)

    assert_empty validator.instance_variable_get(:@warnings)
  end

  def test_audit_payload_includes_warning_diagnostics
    validator = validator_with_diagnostics
    warning = "duplicate asset warning"
    validator.instance_variable_get(:@warnings) << warning
    validator.instance_variable_set(:@manifest_path, Pathname(__FILE__))
    payload = {
      "release_version" => "2026-08-27",
      "municipalities" => [],
      "relationships" => []
    }

    audit = validator.send(:audit_payload, payload)

    assert_equal 1, audit.fetch("warning_count")
    assert_equal [ warning ], audit.fetch("warnings")
    assert_equal 0, audit.fetch("error_count")
  end

  private

  def validator_with_diagnostics
    ValidatePublicInstitutionManifest.allocate.tap do |validator|
      validator.instance_variable_set(:@errors, [])
      validator.instance_variable_set(:@warnings, [])
    end
  end

  def institution(institution_id, document_id, sha256)
    {
      "canonical_id" => institution_id,
      "documents" => [
        {
          "canonical_id" => document_id,
          "assets" => [ { "content_sha256" => sha256 } ]
        }
      ]
    }
  end

  def relationship(source, target, primary: false)
    {
      "source_id" => source,
      "target_id" => target,
      "relationship_type" => "administrative_parent",
      "primary" => primary
    }
  end
end
