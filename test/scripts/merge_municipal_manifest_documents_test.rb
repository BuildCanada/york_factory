# frozen_string_literal: true

require "test_helper"
require Rails.root.join("script/merge_municipal_manifest_documents")

class MergeMunicipalManifestDocumentsTest < ActiveSupport::TestCase
  test "adds audited donor assets without replacing current metadata or duplicating hashes" do
    Dir.mktmpdir do |dir|
      base_path = Pathname(dir).join("base.json")
      donor_path = Pathname(dir).join("donor.json")
      output_path = Pathname(dir).join("output.json")
      base = manifest(website: "https://current.example", assets: [ asset("a") ])
      donor = manifest(website: "https://old.example", assets: [ asset("a"), asset("b") ])
      base_path.write(JSON.generate(base))
      donor_path.write(JSON.generate(donor))

      summary = MergeMunicipalManifestDocuments.new(
        manifest_path: base_path,
        donor_path: donor_path,
        output_path: output_path,
        merged_at: "2026-08-24T23:15:27Z"
      ).run
      result = JSON.parse(output_path.read)
      row = result.fetch("municipalities").sole

      assert_equal "https://current.example", row.fetch("website_url")
      assets = row.fetch("documents").sole.fetch("assets")
      assert_equal %w[a b], assets.pluck("content_sha256")
      assert_equal [ true, false ], assets.pluck("preferred")
      assert_equal [ 1, 2 ], assets.pluck("part_index")
      assert_equal [ 2, 2 ], assets.pluck("part_count")
      assert_equal 0, summary.fetch("imported_documents")
      assert_equal 1, summary.fetch("imported_assets")
      assert_equal 1, result.fetch("merged_document_manifests").length
    end
  end

  test "refuses to merge a different municipal roster" do
    Dir.mktmpdir do |dir|
      base_path = Pathname(dir).join("base.json")
      donor_path = Pathname(dir).join("donor.json")
      base_path.write(JSON.generate(manifest))
      donor = manifest
      donor.fetch("municipalities").sole["canonical_id"] = "ca/on/different"
      donor_path.write(JSON.generate(donor))

      assert_raises(RuntimeError, match: /roster mismatch/) do
        MergeMunicipalManifestDocuments.new(
          manifest_path: base_path,
          donor_path: donor_path,
          output_path: Pathname(dir).join("output.json"),
          merged_at: "2026-08-24T23:15:27Z"
        ).run
      end
    end
  end

  test "normalizes pre-existing assets for every document type" do
    Dir.mktmpdir do |dir|
      base_path = Pathname(dir).join("base.json")
      donor_path = Pathname(dir).join("donor.json")
      payload = manifest
      payload.fetch("municipalities").sole.fetch("documents") << {
        "canonical_id" => "ca/on/example/documents/annual-report/2024/general",
        "document_type" => "annual-report",
        "assets" => [ asset("c"), asset("d") ]
      }
      base_path.write(JSON.generate(payload))
      donor_path.write(JSON.generate(payload))
      output_path = Pathname(dir).join("output.json")

      MergeMunicipalManifestDocuments.new(
        manifest_path: base_path,
        donor_path: donor_path,
        output_path: output_path,
        merged_at: "2026-08-24T23:15:27Z"
      ).run
      annual = JSON.parse(output_path.read).fetch("municipalities").sole.fetch("documents")
        .find { _1.fetch("document_type") == "annual-report" }

      assert_equal [ true, false ], annual.fetch("assets").pluck("preferred")
      assert_equal [ 1, 2 ], annual.fetch("assets").pluck("part_index")
    end
  end

  private

  def manifest(website: "https://example.test", assets: [])
    {
      "release_version" => "2026-08-24",
      "province" => { "code" => "on" },
      "coverage" => [ { "subject" => "financial-statements", "status" => "partial", "notes" => "" } ],
      "municipalities" => [
        {
          "canonical_id" => "ca/on/example",
          "website_url" => website,
          "documents" => [
            {
              "canonical_id" => "ca/on/example/documents/financial-statements/2024/general",
              "document_type" => "financial-statements",
              "assets" => assets
            }
          ]
        }
      ]
    }
  end

  def asset(hash)
    { "content_sha256" => hash, "archive_path" => "sha256/#{hash}.pdf", "preferred" => true }
  end
end
