# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../script/correct_duplicate_annual_report_assets"

class CorrectDuplicateAnnualReportAssetsTest < Minitest::Test
  def test_classifies_only_known_misattributions
    corrector = CorrectDuplicateAnnualReportAssets.allocate
    assert corrector.send(:removal_reason, "bc", "ca/bc/central-saanich", CorrectDuplicateAnnualReportAssets::BC_PAAC)
    assert corrector.send(:removal_reason, "nb", "ca/nb/shippagan", CorrectDuplicateAnnualReportAssets::LE_GOULET_REPORT)
    assert_nil corrector.send(:removal_reason, "nb", CorrectDuplicateAnnualReportAssets::LE_GOULET,
      CorrectDuplicateAnnualReportAssets::LE_GOULET_REPORT)
    assert_nil corrector.send(:removal_reason, "on", "ca/on/example", CorrectDuplicateAnnualReportAssets::BC_PAAC)
  end

  def test_replaces_stale_document_url_after_removing_an_asset
    corrector = CorrectDuplicateAnnualReportAssets.allocate
    corrector.instance_variable_set(:@decisions, [])
    manifest = {
      "municipalities" => [ {
        "canonical_id" => CorrectDuplicateAnnualReportAssets::LE_GOULET,
        "documents" => [ {
          "canonical_id" => "ca/nb/le-goulet/documents/annual-report/2018/general",
          "document_type" => "annual-report",
          "download_url" => "https://wrong.test/nonmunicipal.pdf",
          "assets" => [ { "content_sha256" => CorrectDuplicateAnnualReportAssets::LE_GOULET_REPORT,
            "download_url" => "https://right.test/le-goulet.pdf" } ]
        } ]
      } ]
    }

    corrector.send(:correct_manifest!, "nb", manifest)

    document = manifest.dig("municipalities", 0, "documents", 0)
    assert_equal "https://right.test/le-goulet.pdf", document.fetch("download_url")
    assert_equal [ CorrectDuplicateAnnualReportAssets::LE_GOULET_REPORT ],
      document.fetch("assets").map { _1.fetch("content_sha256") }
  end
end
