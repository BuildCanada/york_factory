# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../script/augment_atlantic_young_entity_predecessors"

class AugmentAtlanticYoungEntityPredecessorsTest < Minitest::Test
  def test_pe_edges_point_from_successors_and_documents_remain_on_issuer
    result = augment("pe")

    edge = result.fetch("relationships").find { _1["target_id"] == "ca/pe/historical/brackley-pre-2017" }
    assert_equal "ca/pe/brackley", edge.fetch("source_id")
    assert_equal "succeeds", edge.fetch("relationship_type")
    assert_equal "2017-12-15", edge.fetch("valid_from")

    successor = institution(result, "ca/pe/brackley")
    assert_equal [ "ca/pe/brackley/documents/financial-statements/2024/general" ], successor.fetch("documents").map { _1.fetch("canonical_id") }
    assert_empty institution(result, "ca/pe/historical/brackley-pre-2017").fetch("documents")

    predecessor = institution(result, "ca/pe/winsloe-south")
    assert_equal "Winsloe South", predecessor.fetch("official_name")
    refute predecessor.key?("official_name_en")
    refute predecessor.key?("official_name_fr")
  end

  def test_ns_uses_english_only_shape_from_english_only_source
    result = augment("ns")
    predecessor = institution(result, "ca/ns/windsor")

    assert_equal "Windsor", predecessor.fetch("official_name")
    refute predecessor.key?("official_name_en")
    refute predecessor.key?("official_name_fr")
    assert_equal %w[en], predecessor.fetch("source_languages")

    edge = result.fetch("relationships").find { _1["target_id"] == "ca/ns/windsor" }
    assert_equal "ca/ns/west-hants", edge.fetch("source_id")
  end

  private

  def augment(province)
    Dir.mktmpdir do |dir|
      profile = AugmentAtlanticYoungEntityPredecessors::PROFILES.fetch(province)
      manifest_path = File.join(dir, "manifest.json")
      source_path = File.join(dir, "source")
      rows = profile.fetch(:transitions).map(&:first).uniq.map do |id|
        {
          "canonical_id" => id,
          "official_name" => id.split("/").last,
          "status" => "active",
          "documents" => id.end_with?("/brackley") ? [ document(id) ] : []
        }
      end
      File.write(manifest_path, JSON.generate("municipalities" => rows, "relationships" => [], "coverage" => []))
      File.write(source_path, "authoritative source")
      return AugmentAtlanticYoungEntityPredecessors.new(
        manifest: manifest_path, province: province, source_files: [ source_path ]
      ).call
    end
  end

  def document(id)
    {
      "canonical_id" => "#{id}/documents/financial-statements/2024/general",
      "document_type" => "financial-statements",
      "assets" => [ { "content_sha256" => "a" * 64 } ]
    }
  end

  def institution(result, id)
    result.fetch("municipalities").find { _1.fetch("canonical_id") == id } || flunk("missing #{id}")
  end
end
