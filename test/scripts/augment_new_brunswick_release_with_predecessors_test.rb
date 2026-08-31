# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../script/augment_new_brunswick_release_with_predecessors"

class AugmentNewBrunswickReleaseWithPredecessorsTest < Minitest::Test
  def test_adds_legal_predecessors_and_moves_documents_without_relabelling_issuers
    Dir.mktmpdir do |dir|
      manifest_path = File.join(dir, "manifest.json")
      audit_path = File.join(dir, "audit.json")
      source_pdf = File.join(dir, "2022-50.pdf")
      File.write(source_pdf, "%PDF-1.4\ntest")
      File.write(manifest_path, JSON.generate(synthetic_manifest))
      File.write(audit_path, JSON.generate(synthetic_audit))

      result = AugmentNewBrunswickReleaseWithPredecessors.new(
        manifest: manifest_path, audit: audit_path, source_pdf: source_pdf
      ).call

      correction = result.fetch("predecessor_identity_correction")
      assert_equal 64, correction.fetch("predecessor_institutions_added")
      assert_equal 64, correction.fetch("succeeds_edges_added")
      assert_equal 12, correction.fetch("financial_statement_works_moved")
      assert_equal 64, result.fetch("relationships").count { _1["relationship_type"] == "succeeds" }

      old_edmundston = institution(result, "ca/nb/historical/edmundston-pre-2023")
      assert_equal [ 2019, 2022 ], financial_years(old_edmundston)
      assert_empty financial_years(institution(result, "ca/nb/edmundston"))
      assert_equal [ 2022 ], financial_years(institution(result, "ca/nb/lac-baker"))

      document_ids = result.fetch("municipalities").flat_map do |row|
        row.fetch("documents", []).map { _1.fetch("canonical_id") }
      end
      assert_equal document_ids.uniq, document_ids
    end
  end

  def test_continuations_and_unincorporated_territory_are_not_predecessors
    successor_ids = AugmentNewBrunswickReleaseWithPredecessors::TRANSITIONS.values.map(&:first)
    refute_includes successor_ids, "ca/nb/bathurst"
    refute_includes successor_ids, "ca/nb/alnwick"
  end

  private

  def synthetic_manifest
    successor_ids = AugmentNewBrunswickReleaseWithPredecessors::TRANSITIONS.values.map(&:first).uniq
    rows = successor_ids.map do |id|
      {
        "canonical_id" => id,
        "official_name_en" => id.split("/").last,
        "municipality_type" => "town",
        "status" => "active",
        "documents" => []
      }
    end
    AugmentNewBrunswickReleaseWithPredecessors::FINANCIAL_DOCUMENT_ISSUERS.each_key.with_index do |(successor_id, year), index|
      institution = rows.find { _1.fetch("canonical_id") == successor_id }
      institution.fetch("documents") << {
        "canonical_id" => "#{successor_id}/documents/financial-statements/#{year}/general",
        "document_type" => "financial-statements",
        "document_variant" => "general",
        "assets" => [ { "content_sha256" => format("%064x", index + 1) } ]
      }
    end
    { "municipalities" => rows, "relationships" => [], "coverage" => [] }
  end

  def synthetic_audit
    sections = AugmentNewBrunswickReleaseWithPredecessors::TRANSITIONS.keys.map do |number|
      {
        "section" => number,
        "classification" => [ 17, 33, 70, 73, 75, 76 ].include?(number) ? "resident_incorporation_new_body" : "amalgamation_new_body",
        "english_subsection_1" => "Authoritative clause for section #{number}."
      }
    end
    { "sections" => sections }
  end

  def institution(result, id)
    result.fetch("municipalities").find { _1.fetch("canonical_id") == id } || flunk("missing #{id}")
  end

  def financial_years(row)
    row.fetch("documents", []).filter_map do |document|
      next unless document["document_type"] == "financial-statements"

      document.fetch("canonical_id")[%r{/([12]\d{3})/}, 1].to_i
    end.sort
  end
end
