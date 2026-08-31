# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../../script/version_national_municipal_release"

class VersionNationalMunicipalReleaseTest < Minitest::Test
  def test_versions_manifests_and_preserves_prior_release_provenance
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      manifest = root.join("on.json")
      manifest.write(JSON.generate(
        "release_version" => "2026-08-24",
        "effective_on" => "2026-08-24",
        "published_at" => "2026-08-24T12:00:00Z",
        "scrape_gaps" => [ "Ontario audited municipal PDFs were not fetched by this adapter." ],
        "municipalities" => []
      ))
      config = root.join("config.json")
      config.write(JSON.generate(
        "generated_at" => "2026-08-24T12:00:00Z",
        "provinces" => [ {
          "province" => "on",
          "manifest_path" => manifest.to_s,
          "scope_note" => "Current Ontario municipalities with at least one validated downloaded financial statement."
        } ]
      ))
      output_config = root.join("release", "config.json")

      VersionNationalMunicipalRelease.new(
        config_path: config,
        output_dir: root.join("release", "manifests"),
        output_config: output_config,
        version: "2026-08-27",
        published_at: "2026-08-27T18:00:00Z"
      ).run

      released_config = JSON.parse(output_config.read)
      released_manifest = JSON.parse(File.read(released_config.dig("provinces", 0, "manifest_path")))
      assert_equal "2026-08-27", released_manifest.fetch("release_version")
      assert_equal "2026-08-27", released_manifest.fetch("effective_on")
      assert_equal "2026-08-27T18:00:00Z", released_manifest.fetch("published_at")
      assert_equal Digest::SHA256.file(manifest).hexdigest,
        released_manifest.dig("release_provenance", "derived_from_manifest_sha256")
      assert_equal "2026-08-24", released_manifest.dig("release_provenance", "prior_release_version")
      refute released_manifest.fetch("scrape_gaps").any? { |gap| gap.include?("were not fetched") }
      assert_equal "final_versioned", released_config.fetch("template_status")
      assert_equal Digest::SHA256.file(released_config.dig("provinces", 0, "manifest_path")).hexdigest,
        released_config.dig("provinces", 0, "manifest_sha256")
      assert_equal "Current Ontario municipalities.", released_config.dig("provinces", 0, "scope_note")
    end
  end
end
