# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "../../script/audit_municipal_financial_statement_assets"

class MunicipalHybridPdfOcrTest < Minitest::Test
  class HybridScraper
    attr_reader :ocr_options

    def initialize
      @ocr_options = []
    end

    attr_reader :pdf_text_options

    def pdf_text(_bytes, max_pages:, fallback_to_ocr:)
      raise "expected a full embedded-text pass" unless max_pages.nil?

      @pdf_text_options = { max_pages: max_pages, fallback_to_ocr: fallback_to_ocr }
      "District of Example annual report"
    end

    def ocr_pdf_text(_bytes, **options)
      @ocr_options << options
      "SCANNED Independent Auditor's Report District of Example " \
        "Consolidated Financial Statements for the year ended December 31, 2022"
    end

    def pdf_page_count(_bytes)
      75
    end

    def official_name(_row)
      "District of Example"
    end

    def institution_matches?(_text, _name)
      true
    end

    def document_types(evidence, _candidate)
      evidence.include?("SCANNED") ? [ "financial-statements" ] : []
    end

    def financial_statement_fiscal_year(text, max_bytes:)
      raise "expected bounded validation text" unless max_bytes == 1_000_000

      text.include?("SCANNED") ? 2022 : nil
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end
  end

  class HybridYearScraper < HybridScraper
    def document_types(_evidence, _candidate)
      [ "financial-statements" ]
    end
  end

  class HybridNameScraper < HybridScraper
    def institution_matches?(text, _name)
      text.include?("SCANNED")
    end
  end


  class LateHybridScraper < HybridScraper
    def ocr_pdf_text(_bytes, **options)
      @ocr_options << options
      return "unrelated scanned page" if options.fetch(:last_page) <= 40

      "SCANNED Independent Auditor's Report District of Example " \
        "Consolidated Financial Statements for the year ended December 31, 2022"
    end
  end

  def test_falls_back_to_bounded_ocr_when_scanned_pages_contain_type_and_year
    scraper = HybridScraper.new
    validate_hybrid_asset!(scraper)

    assert_equal({ max_pages: nil, fallback_to_ocr: false }, scraper.pdf_text_options)
    assert_equal [ ocr_range(1, 8) ], scraper.ocr_options
  end

  def test_falls_back_to_bounded_ocr_when_scanned_pages_contain_only_the_missing_year
    scraper = HybridYearScraper.new
    validate_hybrid_asset!(scraper)

    assert_equal [ ocr_range(1, 8) ], scraper.ocr_options
  end

  def test_falls_back_to_bounded_ocr_when_only_scanned_pages_identify_the_issuer
    scraper = HybridNameScraper.new
    validate_hybrid_asset!(scraper)

    assert_equal [ ocr_range(1, 8) ], scraper.ocr_options
  end

  def test_incremental_ocr_reaches_evidence_after_page_forty_without_reprocessing_pages
    scraper = LateHybridScraper.new
    validate_hybrid_asset!(scraper)

    assert_equal [
      ocr_range(1, 8), ocr_range(9, 16), ocr_range(17, 24),
      ocr_range(25, 32), ocr_range(33, 40), ocr_range(41, 48)
    ], scraper.ocr_options
  end

  def test_row_aware_check_rejects_a_legal_entity_extending_the_expected_issuer
    scraper = MunicipalFinancialReportScraper.new(
      manifest_path: "/tmp/not-read.json",
      output_dir: "/tmp/not-written",
      retrieved_at: "2026-08-25T14:32:57Z"
    )
    evidence = "Independent Auditor's Report. We have audited the financial statements " \
      "of the Islands Trust Conservancy. Statement of Financial Position."
    candidate = {
      "label" => "Islands Trust Conservancy 2022-23 Annual Report",
      "url" => "https://islandstrust.bc.ca/conservancy-annual-report.pdf"
    }

    assert_includes scraper.send(:document_types, evidence, candidate), "financial-statements"

    auditor = AuditMunicipalFinancialStatementAssets.allocate
    auditor.instance_variable_set(:@scraper, scraper)
    assert auditor.send(:subsidiary_issuer_extension?, evidence, "Islands Trust")
    refute auditor.send(:subsidiary_issuer_extension?, evidence, "Islands Trust Conservancy")
  end

  def test_accepts_a_municipal_audit_with_a_later_subsidiary_appendix
    scraper = MunicipalFinancialReportScraper.new(
      manifest_path: "/tmp/not-read.json",
      output_dir: "/tmp/not-written",
      retrieved_at: "2026-08-25T14:32:57Z"
    )
    evidence = "Independent Auditor's Report. We have audited the consolidated financial statements of " \
      "the Town of Example. Statement of Financial Position.\f" \
      "Independent Auditor's Report. We have audited the financial statements of the Town of Example Trust Fund."
    candidate = {
      "label" => "Town of Example 2024 Consolidated Financial Statements",
      "url" => "https://example.ca/2024-consolidated-financial-statements.pdf"
    }

    assert_includes scraper.send(:document_types, evidence, candidate), "financial-statements"
  end

  def test_validation_slices_do_not_split_utf8_characters
    scraper = MunicipalFinancialReportScraper.new(
      manifest_path: "/tmp/not-read.json",
      output_dir: "/tmp/not-written",
      retrieved_at: "2026-08-25T14:32:57Z"
    )
    text = ("a" * 9) + "é"

    slice = scraper.send(:safe_byteslice, text, 10)

    assert slice.valid_encoding?
    assert slice.start_with?("a" * 9)
  end

  def test_legacy_singular_auditor_wording_requires_matching_singular_opinion
    scraper = real_scraper
    candidate = { "label" => "2015 Financial Statements", "url" => "https://example.test/2015.pdf" }
    evidence = "AUDITOR'S REPORT I have audited the consolidated financial statements. " \
      "Statement of Financial Position. In my opinion, the statements present fairly."

    assert_includes scraper.send(:document_types, evidence, candidate), "financial-statements"
    refute_includes scraper.send(:document_types, evidence.sub("my opinion", "our opinion"), candidate),
      "financial-statements"
  end

  def test_legacy_ocr_pipe_pronoun_requires_singular_responsibility_evidence
    scraper = real_scraper
    candidate = { "label" => "2011 Financial Statements", "url" => "https://example.test/2011.pdf" }
    evidence = "AUDITOR'S REPORT | have audited the consolidated financial statements. " \
      "My responsibility is to express an opinion on the consolidated financial statements."

    assert_includes scraper.send(:document_types, evidence, candidate), "financial-statements"
    refute_includes scraper.send(:document_types, evidence.sub("My responsibility", "Our responsibility"), candidate),
      "financial-statements"
  end

  def test_name_matching_supports_editorial_qualifiers_and_inuit_government_forms
    scraper = real_scraper

    assert scraper.send(:institution_matches?, "Town of Charlottetown Financial Statements", "Charlottetown (Labrador)")
    assert scraper.send(:institution_matches?, "Nain Inuit Community Government", "Nain")
    refute scraper.send(:institution_matches?, "Nain Airport Authority", "Nain")
  end

  def test_name_matching_supports_french_elision_and_quebec_cover_fields
    scraper = real_scraper

    assert scraper.send(:institution_matches?, "Village d'Abercorn | 46005", "Abercorn")
    assert scraper.send(:institution_matches?, "Municipalité d'Ange-Gardien | 55008", "Ange-Gardien")
    assert scraper.send(:institution_matches?, "Nom Alma Code géographique 93042", "Alma")
    assert scraper.send(:institution_matches?, "Nom Oka Code géographique 72032", "Oka")
    refute scraper.send(:institution_matches?, "Okapi conservation report", "Oka")
  end

  def test_quebec_geographic_code_proves_historical_issuer_after_a_rename
    auditor = AuditMunicipalFinancialStatementAssets.allocate
    auditor.instance_variable_set(:@scraper, real_scraper)
    row = {
      "canonical_id" => "ca/qc/mont-blanc",
      "identifiers" => [ { "scheme" => "qc.code-geographique", "value" => "78047" } ]
    }
    cover = "Nom : Saint-Faustin--Lac-Carré Code géographique : 78047"

    assert auditor.send(:institution_matches_row?, cover, row, "Mont-Blanc")
    refute auditor.send(:institution_matches_row?, "Total 78047", row, "Mont-Blanc")
    refute auditor.send(:institution_matches_row?, "Code géographique 99999", row, "Mont-Blanc")
  end

  def test_name_matching_normalizes_municipal_numeric_designators
    scraper = real_scraper

    assert scraper.send(:institution_matches?, "Improvement District No. 9 Financial Statements",
      "Improvement District No. 09 (Banff)")
    assert scraper.send(:institution_matches?, "County of Stettler #6 Financial Statements",
      "County of Stettler No. 6")
    refute scraper.send(:institution_matches?, "Improvement District No. 19 Financial Statements",
      "Improvement District No. 09 (Banff)")
  end

  def test_fiscal_year_prefers_statement_cover_over_restated_comparative_year
    scraper = real_scraper
    evidence = "CITY OF EXAMPLE CONSOLIDATED FINANCIAL STATEMENTS December 31, 2019 " \
      "Independent Auditor's Report. Comparative information presented for the year ended " \
      "December 31, 2018 has been restated."

    assert_equal 2019, scraper.send(:financial_statement_fiscal_year, evidence)
  end

  def test_report_page_discovers_year_labelled_opaque_download_endpoint
    scraper = real_scraper
    links = scraper.send(
      :extract_report_links,
      '<a href="/public/download/files/316872">2015</a>',
      "https://www.stephenville.ca/town-hall/audited-financial-statements",
      report_context: true
    )

    assert_equal [ "https://www.stephenville.ca/public/download/files/316872" ], links.map { _1.fetch("url") }
  end

  def test_ocr_orientation_score_prefers_readable_sideways_financial_cover
    scraper = real_scraper
    sideways = "6102 LE sequieseq squowayeys 1ejoueul NOLHALNIM 10 NMOL"
    upright = "TOWN OF WINTERTON Financial Statements December 31, 2019"

    assert_operator scraper.send(:ocr_orientation_score, upright), :>=,
      MunicipalFinancialReportScraper::OCR_ORIENTATION_SCORE_THRESHOLD
    assert_operator scraper.send(:ocr_orientation_score, upright), :>,
      scraper.send(:ocr_orientation_score, sideways)
  end

  def test_normalize_accepts_binary_encoded_ocr_text
    scraper = real_scraper
    binary_text = "États financiers audités".b

    assert_equal "etats financiers audites", scraper.send(:normalize, binary_text)
  end

  def test_normalize_scrubs_invalid_binary_ocr_bytes
    scraper = real_scraper

    assert_equal "town financial statements", scraper.send(
      :normalize,
      "Town \xFF Financial Statements".b
    )
  end

  def test_asset_auditor_rejects_disagreeing_canonical_and_fiscal_years
    auditor = AuditMunicipalFinancialStatementAssets.allocate
    document = {
      "canonical_id" => "ca/on/example/documents/financial-statements/2024/general",
      "fiscal_period_end" => "2023-12-31"
    }

    error = assert_raises(RuntimeError) { auditor.send(:document_fiscal_year, document) }

    assert_equal "document canonical and fiscal years disagree: 2024 != 2023", error.message
  end

  private

  def real_scraper
    MunicipalFinancialReportScraper.new(
      manifest_path: "/tmp/not-read.json",
      output_dir: "/tmp/not-written",
      retrieved_at: "2026-08-25T14:32:57Z"
    )
  end

  def ocr_range(first_page, last_page)
    { first_page: first_page, last_page: last_page, dpi: 120, allow_empty: true }
  end

  def validate_hybrid_asset!(scraper)
    Dir.mktmpdir do |directory|
      bytes = "%PDF-hybrid-fixture"
      hash = Digest::SHA256.hexdigest(bytes)
      asset_root = Pathname(directory)
      relative_path = Pathname("sha256").join(hash[0, 2], "#{hash}.pdf")
      asset_root.join(relative_path).dirname.mkpath
      asset_root.join(relative_path).binwrite(bytes)
      auditor = AuditMunicipalFinancialStatementAssets.allocate
      auditor.instance_variable_set(:@asset_root, asset_root)
      auditor.instance_variable_set(:@scraper, scraper)

      auditor.send(
        :validate_asset!,
        { "canonical_id" => "ca/bc/example", "official_name" => "District of Example" },
        {
          "canonical_id" => "ca/bc/example/documents/financial-statements/2022/general",
          "title" => "2022 Annual Report",
          "download_url" => "https://example.ca/annual-report-2022.pdf"
        },
        { "content_sha256" => hash, "archive_path" => relative_path.to_s }
      )
    end
  end
end
