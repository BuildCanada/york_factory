# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../script/reassign_manifest_financial_statement_years"

class ReassignManifestFinancialStatementYearsTest < Minitest::Test
  def test_moves_mismatched_assets_atomically_and_merges_corrected_year_collisions
    Dir.mktmpdir do |directory|
      fixture = build_fixture(directory)
      run_transform(fixture)
      output = JSON.parse(File.read(fixture.fetch(:output_path)))
      documents = output.fetch("municipalities").first.fetch("documents")

      assert_equal [ "ca/bc/example/documents/financial-statements/2023/general" ],
        documents.map { |document| document.fetch("canonical_id") }
      assert_equal %w[a b], documents.first.fetch("assets").map { |asset| asset.fetch("marker") }.sort
      assert_equal 1, documents.first.fetch("assets").count { |asset| asset.fetch("preferred") }
      assert_equal 1, output.dig("financial_statement_fiscal_year_reassignment", "moved_asset_count")
    end
  end

  def test_handles_reversed_year_sequences_without_move_order_corruption
    Dir.mktmpdir do |directory|
      fixture = build_fixture(directory, reverse_second_asset: true)
      run_transform(fixture)
      output = JSON.parse(File.read(fixture.fetch(:output_path)))
      documents = output.fetch("municipalities").first.fetch("documents").to_h do |document|
        [ document.fetch("canonical_id"), document ]
      end

      assert_equal [ "b" ], documents.fetch("ca/bc/example/documents/financial-statements/2022/general")
        .fetch("assets").map { _1.fetch("marker") }
      assert_equal [ "a" ], documents.fetch("ca/bc/example/documents/financial-statements/2023/general")
        .fetch("assets").map { _1.fetch("marker") }
    end
  end

  def test_leaves_a_content_year_negative_control_untouched_when_audit_reports_no_mismatch
    Dir.mktmpdir do |directory|
      fixture = build_fixture(directory, include_mismatch: false)
      error = assert_raises(RuntimeError) { run_transform(fixture) }

      assert_equal "strict audit contained no fiscal-year mismatches", error.message
      refute File.exist?(fixture.fetch(:output_path))
    end
  end

  def test_collapses_same_asset_duplicate_variants_within_the_same_fiscal_year
    Dir.mktmpdir do |directory|
      fixture = build_fixture(directory)
      manifest = JSON.parse(File.read(fixture.fetch(:manifest_path)))
      original = manifest.fetch("municipalities").first.fetch("documents").last
      duplicate = original.merge(
        "canonical_id" => original.fetch("canonical_id").sub("/general", "/consolidated"),
        "assets" => original.fetch("assets").map(&:dup)
      )
      manifest.fetch("municipalities").first.fetch("documents") << duplicate
      fixture.fetch(:manifest_path).write(JSON.generate(manifest))
      audit = JSON.parse(File.read(fixture.fetch(:audit_path)))
      audit["source_manifest_sha256"] = Digest::SHA256.file(fixture.fetch(:manifest_path)).hexdigest
      fixture.fetch(:audit_path).write(JSON.generate(audit))

      run_transform(fixture)
      output = JSON.parse(File.read(fixture.fetch(:output_path)))
      assets = output.fetch("municipalities").first.fetch("documents").flat_map { _1.fetch("assets") }

      assert_equal 2, assets.map { _1.fetch("content_sha256") }.uniq.length
      assert_equal 2, assets.length
    end
  end

  private

  def build_fixture(directory, reverse_second_asset: false, include_mismatch: true)
    asset_root = Pathname(directory).join("assets")
    asset_a = write_asset(asset_root, "a", "%PDF-a")
    asset_b = write_asset(asset_root, "b", "%PDF-b")
    documents = [
      document(2022, asset_a),
      document(2023, asset_b)
    ]
    manifest = {
      "municipalities" => [
        {
          "canonical_id" => "ca/bc/example",
          "official_name" => "Example",
          "documents" => documents
        }
      ]
    }
    manifest_path = Pathname(directory).join("manifest.json")
    manifest_path.write(JSON.generate(manifest))
    mismatches = []
    if include_mismatch
      mismatches << rejection(asset_a, 2022, 2023)
      mismatches << rejection(asset_b, 2023, 2022) if reverse_second_asset
    end
    audit = {
      "source_manifest_path" => manifest_path.expand_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(manifest_path).hexdigest,
      "rejected_assets" => mismatches
    }
    audit_path = Pathname(directory).join("audit.json")
    audit_path.write(JSON.generate(audit))
    {
      manifest_path: manifest_path,
      audit_path: audit_path,
      output_path: Pathname(directory).join("output.json"),
      asset_root: asset_root
    }
  end

  def run_transform(fixture)
    ReassignManifestFinancialStatementYears.new(
      manifest_path: fixture.fetch(:manifest_path),
      audit_path: fixture.fetch(:audit_path),
      output_path: fixture.fetch(:output_path),
      transformed_at: "2026-08-25T14:00:00Z",
      asset_root: fixture.fetch(:asset_root)
    ).run
  end

  def write_asset(asset_root, marker, bytes)
    sha = Digest::SHA256.hexdigest(bytes)
    relative = Pathname("sha256").join(sha[0, 2], "#{sha}.pdf")
    path = asset_root.join(relative)
    FileUtils.mkdir_p(path.dirname)
    path.binwrite(bytes)
    {
      "marker" => marker,
      "content_sha256" => sha,
      "archive_path" => relative.to_s,
      "preferred" => true
    }
  end

  def document(year, asset)
    {
      "canonical_id" => "ca/bc/example/documents/financial-statements/#{year}/general",
      "document_type" => "financial-statements",
      "title" => "Example Audited Financial Statements — #{year}",
      "fiscal_period_start" => "#{year}-01-01",
      "fiscal_period_end" => "#{year}-12-31",
      "assets" => [ asset ]
    }
  end

  def rejection(asset, manifest_year, verified_year)
    {
      "institution_id" => "ca/bc/example",
      "document_id" => "ca/bc/example/documents/financial-statements/#{manifest_year}/general",
      "content_sha256" => asset.fetch("content_sha256"),
      "archive_path" => asset.fetch("archive_path"),
      "reason" => "PDF fiscal year #{verified_year} does not match document fiscal year #{manifest_year}"
    }
  end
end
