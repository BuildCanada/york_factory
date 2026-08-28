# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../script/archive_explicit_municipal_financial_reports"

class ArchiveExplicitMunicipalFinancialReportsTest < Minitest::Test
  def test_candidate_preserves_structured_wayback_provenance
    archiver = ArchiveExplicitMunicipalFinancialReports.allocate
    report = {
      "canonical_id" => "ca/nl/fogo-island",
      "label" => "Town of Fogo Island Audited Financial Statements 2023",
      "source_page_url" => "https://www.townoffogoisland.ca/home/files/bylaws_rates_regulations/",
      "download_url" => "https://web.archive.org/web/20250803040642id_/https://www.townoffogoisland.ca/2023.pdf",
      "original_url" => "https://www.townoffogoisland.ca/2023.pdf",
      "wayback_timestamp" => "20250803040642",
      "wayback_digest" => "JKEBNYAFWM4EUPZMALYGC4T6A4EFN2HJ",
      "ignored" => "not copied"
    }

    candidate = archiver.send(:candidate_for, report)

    assert_equal report.fetch("download_url"), candidate.fetch("url")
    assert_equal report.fetch("original_url"), candidate.fetch("original_url")
    assert_equal "20250803040642", candidate.fetch("wayback_timestamp")
    assert_equal "JKEBNYAFWM4EUPZMALYGC4T6A4EFN2HJ", candidate.fetch("wayback_digest")
    refute candidate.key?("ignored")
  end
end
