# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../script/sanitize_municipal_report_batch"

class SanitizeMunicipalReportBatchTest < Minitest::Test
  def setup
    @sanitizer = SanitizeMunicipalReportBatch.allocate
  end

  def test_content_fiscal_year_overrides_upload_year
    report = {
      "year" => 2026,
      "download_url" => "https://example.ca/uploads/2026/statements.pdf",
      "source_page_url" => "https://example.ca/finance",
      "title" => "2026 Financial Statements"
    }
    text = "Consolidated Financial Statements for the year ended December 31, 2025"

    assert_equal 2025, @sanitizer.send(:corrected_year, report, text)
  end

  def test_falls_back_to_explicit_report_year_when_content_has_no_period
    report = {
      "year" => 2024,
      "download_url" => "https://example.ca/statements.pdf",
      "source_page_url" => "https://example.ca/finance",
      "title" => "Audited Financial Statements"
    }

    assert_equal 2024, @sanitizer.send(:corrected_year, report, "Independent Auditor's Report")
  end

  def test_preserves_verified_split_bundle_year_over_response_publication_year
    report = {
      "year" => 2015,
      "download_url" => "https://example.ca/access-to-information/2025/response.pdf",
      "source_page_url" => "https://example.ca/requests/2025",
      "title" => "Rapport financier consolidé 2015",
      "verification" => { "split_page_range_verified" => true }
    }

    assert_equal 2015, @sanitizer.send(:corrected_year, report, "")
  end

  def test_content_year_uses_the_earliest_primary_period_evidence
    report = {
      "year" => 2018,
      "download_url" => "https://example.ca/statements.pdf",
      "source_page_url" => "https://example.ca/finance",
      "title" => "Audited Financial Statements"
    }
    text = "Consolidated Financial Statements December 31, 2019. " \
      "Comparative information for the year ended December 31, 2018 was restated."

    assert_equal 2019, @sanitizer.send(:corrected_year, report, text)
  end

  def test_rejects_greater_sudbury_utilities_corporate_statements
    [
      "2009 - Consolidated Financial Statements Of The Greater Sudbury Utilities Inc.",
      "2010 - Consolidated Financial Statements Of The Greater Sudbury Utilities Inc."
    ].each do |title|
      report = financial_statement_report(title)

      assert_equal "subsidiary or trust financial statements, not the reporting institution's statements",
        @sanitizer.send(:rejection_reason, report, "")
    end
  end

  def test_retains_city_statements_that_discuss_utility_operations
    report = financial_statement_report("Consolidated Financial Statements of the City of Greater Sudbury")
    text = "The municipality reports utility revenue and utility expenses in its consolidated operations."

    assert_nil @sanitizer.send(:rejection_reason, report, text)
  end

  def test_retains_municipal_statements_with_bare_plural_utilities_fund_title
    report = financial_statement_report("Consolidated Financial Statements — General and Utilities Funds")

    assert_nil @sanitizer.send(:rejection_reason, report, "")
  end

  private

  def financial_statement_report(title)
    {
      "year" => 2024,
      "document_type" => "financial-statements",
      "download_url" => "https://example.ca/statements.pdf",
      "source_page_url" => "https://example.ca/finance",
      "title" => title
    }
  end
end
