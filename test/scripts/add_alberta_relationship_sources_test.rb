# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../script/add_alberta_relationship_sources"

class AddAlbertaRelationshipSourcesTest < Minitest::Test
  def test_adds_authoritative_sources_and_records_pinned_provenance
    Dir.mktmpdir do |directory|
      manifest_path = Pathname(directory).join("input.json")
      output_path = Pathname(directory).join("output.json")
      manifest_path.write(JSON.generate(manifest))

      AddAlbertaRelationshipSources.new(
        manifest_path: manifest_path,
        output_path: output_path,
        transformed_at: "2026-08-25T15:00:00Z"
      ).run

      result = JSON.parse(output_path.read)
      assert_equal 4, result.dig("relationship_source_augmentation", "changed_relationship_count")
      assert_equal Digest::SHA256.file(manifest_path).hexdigest,
        result.dig("relationship_source_augmentation", "source_manifest_sha256")
      assert result.fetch("relationships").all? { |relationship| relationship["source_url"].to_s.start_with?("https://") }
    end
  end

  def test_refuses_a_conflicting_existing_source
    Dir.mktmpdir do |directory|
      manifest_path = Pathname(directory).join("input.json")
      output_path = Pathname(directory).join("output.json")
      payload = manifest
      payload.fetch("relationships").first["source_url"] = "https://example.invalid/wrong"
      manifest_path.write(JSON.generate(payload))

      error = assert_raises(RuntimeError) do
        AddAlbertaRelationshipSources.new(
          manifest_path: manifest_path,
          output_path: output_path,
          transformed_at: "2026-08-25T15:00:00Z"
        ).run
      end
      assert_match(/conflicting source URL/, error.message)
      refute output_path.exist?
    end
  end

  private

  def manifest
    {
      "province" => { "code" => "ab" },
      "municipalities" => [],
      "relationships" => [
        relationship("ca/ab/diamond-valley", "succeeds", "ca/ab/black-diamond"),
        relationship("ca/ab/diamond-valley", "succeeds", "ca/ab/turner-valley"),
        relationship("ca/ab/bonnyville-no-87", "succeeds", "ca/ab/improvement-district-no-349"),
        relationship("ca/ab/special-areas-board", "controlled_by", "ca/ab")
      ]
    }
  end

  def relationship(source_id, relationship_type, target_id)
    {
      "source_id" => source_id,
      "relationship_type" => relationship_type,
      "target_id" => target_id
    }
  end
end
