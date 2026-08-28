# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "tmpdir"
require_relative "../../script/merge_municipal_financial_report_batch"

class MergeMunicipalFinancialReportBatchTest < Minitest::Test
  def test_reviewed_batch_keeps_content_proven_year_despite_upload_year_url
    merger = MergeMunicipalFinancialReportBatch.allocate
    merger.instance_variable_set(:@reviewed_batch, true)
    report = {
      "year" => 2024,
      "download_url" => "https://example.ca/uploads/2025/financial-statements.pdf",
      "source_page_url" => "https://example.ca/reports/2025",
      "title" => "2025 Financial Statements"
    }

    assert_equal 2024, merger.send(:corrected_year, report)
  end

  def test_review_provenance_requires_the_pinned_raw_batch_hash
    Dir.mktmpdir do |directory|
      path = Pathname(directory).join("raw.json")
      path.write("raw batch")
      merger = MergeMunicipalFinancialReportBatch.allocate
      valid = {
        "review" => {
          "input_path" => path.to_s,
          "input_sha256" => Digest::SHA256.file(path).hexdigest
        }
      }
      assert merger.send(:verify_review_provenance!, valid)

      valid.fetch("review")["input_sha256"] = "0" * 64
      assert_raises(RuntimeError) { merger.send(:verify_review_provenance!, valid) }
    end
  end

  def test_update_audit_preserves_legacy_municipalities_bucket
    Dir.mktmpdir do |directory|
      batch_path = Pathname(directory).join("batch.json")
      batch_path.write("{}")
      merger = MergeMunicipalFinancialReportBatch.allocate
      merger.instance_variable_set(:@batch_path, batch_path)
      manifest = { "scrape_audit" => { "batches" => [], "municipalities" => {} } }
      batch = {
        "batch" => "test-batch",
        "retrieved_at" => "2026-08-25T00:00:00Z",
        "institutions" => [
          {
            "canonical_id" => "ca/ab/test",
            "searched_locations" => [],
            "gaps" => [],
            "candidate_count" => 1,
            "validated_report_count" => 1
          }
        ]
      }

      merger.send(:update_audit!, manifest, batch)

      assert_equal 1, manifest.dig("scrape_audit", "municipalities", "ca/ab/test").length
      refute manifest.dig("scrape_audit", "institutions")
    end
  end
end
