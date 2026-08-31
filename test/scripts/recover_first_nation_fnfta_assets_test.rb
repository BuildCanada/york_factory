# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../script/recover_first_nation_fnfta_assets"

class RecoverFirstNationFnftaAssetsTest < Minitest::Test
  def test_recovers_verified_legacy_pdf_into_content_addressed_inventory
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      legacy = root.join("legacy", "ISC_1", "2024")
      legacy.join("source").mkpath
      pdf = "%PDF-1.4\nverified\n%%EOF\n"
      legacy.join("source", "financial_statement.pdf").binwrite(pdf)
      legacy.join("metadata.json").write(JSON.generate(
        "created_at" => "2026-01-01T00:00:00Z",
        "source_files" => { "financial_statement" => {
          "file_size_bytes" => pdf.bytesize, "is_corrupted" => false, "error_message" => nil,
          "original_path" => "first-nations/1/example.pdf"
        } }
      ))
      manifest = root.join("manifest.json")
      manifest.write(JSON.generate(
        "release_version" => "2026-08-24",
        "bands" => [ { "canonical_id" => "ca/fn/example", "band_number" => 1 } ]
      ))
      inventory = root.join("inventory.json")
      inventory.write(JSON.generate(
        "release_version" => "2026-08-24",
        "assets" => [ {
          "document_canonical_id" => "ca/fn/example/documents/financial-statements/2024/consolidated",
          "download_url" => "https://example.test/statement",
          "error" => "transient HTTP 500"
        } ]
      ))
      output = root.join("recovered.json")
      audit = root.join("audit.json")

      RecoverFirstNationFnftaAssets.new(
        manifest_path: manifest, inventory_path: inventory, legacy_root: root.join("legacy"),
        asset_root: root.join("assets"), output_path: output, audit_path: audit,
        recovered_at: "2026-08-27T18:00:00Z"
      ).run

      asset = JSON.parse(output.read).fetch("assets").first
      assert_nil asset["error"]
      assert_equal Digest::SHA256.hexdigest(pdf), asset.fetch("content_sha256")
      assert root.join("assets", asset.fetch("archive_path")).file?
      assert_equal 1, JSON.parse(audit.read).fetch("recovered_asset_count")
    end
  end
end
