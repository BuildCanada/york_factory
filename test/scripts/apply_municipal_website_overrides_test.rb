# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../../script/apply_municipal_website_overrides"

class ApplyMunicipalWebsiteOverridesTest < Minitest::Test
  def test_preserves_directory_profile_and_records_provenance
    Dir.mktmpdir do |directory|
      manifest = File.join(directory, "manifest.json")
      overrides = File.join(directory, "overrides.json")
      output = File.join(directory, "output.json")
      File.write(manifest, JSON.generate(
        "municipalities" => [
          {
            "canonical_id" => "ca/nl/example",
            "website_url" => "https://municipalnl.ca/town/example/",
            "website_gap" => "No standalone website found."
          }
        ]
      ))
      File.write(overrides, JSON.generate(
        "overrides" => [
          {
            "canonical_id" => "ca/nl/example",
            "website_url" => "https://example.ca/",
            "source_url" => "https://example.ca/reports/"
          }
        ]
      ))

      ApplyMunicipalWebsiteOverrides.new(
        manifest_path: manifest,
        overrides_path: overrides,
        output_path: output,
        transformed_at: "2026-08-25T23:58:00Z"
      ).run
      result = JSON.parse(File.read(output))
      row = result.fetch("municipalities").first

      assert_equal "https://example.ca/", row.fetch("website_url")
      assert_equal "https://example.ca/reports/", row.fetch("website_source_url")
      assert_equal "https://municipalnl.ca/town/example/", row.fetch("website_directory_profile_url")
      refute row.key?("website_gap")
      assert_equal 1, result.dig("municipal_website_overrides", "change_count")
    end
  end
end
