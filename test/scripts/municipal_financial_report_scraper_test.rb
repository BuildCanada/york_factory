# frozen_string_literal: true

require "test_helper"
require Rails.root.join("script/scrape_municipal_financial_reports")

class MunicipalFinancialReportScraperTest < ActiveSupport::TestCase
  setup do
    @scraper = MunicipalFinancialReportScraper.new(
      manifest_path: "/tmp/not-read.json",
      output_dir: "/tmp/not-written",
      retrieved_at: "2026-08-24T00:00:00Z"
    )
  end

  test "matches Ontario legal names whose form follows the place name" do
    assert @scraper.send(
      :institution_matches?,
      "CORPORATION OF THE TOWNSHIP OF ADELAIDE METCALFE Financial Statements",
      "Adelaide-Metcalfe, Township of"
    )
    assert @scraper.send(
      :institution_matches?,
      "THE CORPORATION OF THE COUNTY OF BRANT Independent Auditor's Report",
      "Brant, County of"
    )
  end

  test "normalizes malformed non-web links without aborting an institution crawl" do
    assert_equal "mailto:", @scraper.send(:normalized_url, "mailto:")
  end

  test "matches a government whose audited statement uses its bare legal name" do
    assert @scraper.send(
      :institution_matches?,
      "BEAURIVAGE Consolidated Financial Statements December 31, 2024",
      "Beaurivage"
    )
  end

  test "uses the canonical official name before a French-only label fallback" do
    row = {
      "official_name" => "Municipality of the District of Argyle",
      "official_name_fr" => "Municipalité d'Argyle"
    }

    assert_equal "Municipality of the District of Argyle", @scraper.send(:official_name, row)
    assert @scraper.send(
      :institution_matches?,
      "MUNICIPALITY OF THE DISTRICT OF ARGYLE Consolidated Financial Statements",
      @scraper.send(:official_name, row)
    )
  end

  test "matches an official name when the statement omits a geographic qualifier" do
    assert @scraper.send(
      :institution_matches?,
      "TOWN OF CHARLOTTETOWN Consolidated Financial Statements",
      "Charlottetown (Labrador)"
    )
  end

  test "matches an Inuit community government whose short official name is used in the ontology" do
    assert @scraper.send(
      :institution_matches?,
      "NAIN INUIT COMMUNITY GOVERNMENT Financial Statements",
      "Nain"
    )

    assert_not @scraper.send(
      :institution_matches?,
      "NAIN AIRPORT Financial Statements",
      "Nain"
    )
  end

  test "does not match a different municipality" do
    assert_not @scraper.send(
      :institution_matches?,
      "CORPORATION OF THE TOWNSHIP OF ADELAIDE METCALFE Financial Statements",
      "Adjala-Tosorontio, Township of"
    )
  end

  test "requires an auditor report before classifying a financial statement" do
    types = @scraper.send(
      :document_types,
      "Town of Ajax Form 4 Candidate Financial Statement election campaign",
      { "label" => "Form 4 Financial Statement", "url" => "https://ajax.ca/elections/form-4.pdf" }
    )

    assert_not_includes types, "financial-statements"
  end

  test "explicit statement filenames override a budget container but not election filings" do
    assert_not @scraper.send(
      :excluded_report_evidence?,
      "https://www5.moncton.ca/docs/budget/2024_Consolidated_Financial_Statements.pdf"
    )
    assert @scraper.send(
      :excluded_report_evidence?,
      "https://example.ca/election/form-4-candidate-financial-statement.pdf"
    )
    assert @scraper.send(
      :excluded_report_evidence?,
      "https://example.ca/2023_Unaudited_Financial_Statement.pdf"
    )
  end

  test "rejects an audited statement for a municipal subsidiary" do
    types = @scraper.send(
      :document_types,
      "Independent Auditor's Report Armour Community Centre Arena Financial Statements " \
        "Statement of Financial Position",
      { "label" => "Arena Financial Statements", "url" => "https://armourtownship.ca/arena-financial-statements.pdf" }
    )

    assert_not_includes types, "financial-statements"
  end

  test "accepts independently audited consolidated municipal statements" do
    types = @scraper.send(
      :document_types,
      "Independent Auditor's Report The Corporation of the Township of Adelaide Metcalfe " \
        "Consolidated Financial Statements Statement of Financial Position",
      { "label" => "2024 Audited Financial Statements", "url" => "https://example.ca/2024-financial-statements.pdf" }
    )

    assert_includes types, "financial-statements"
  end

  test "prefers the fiscal year in PDF text over the upload year in the link" do
    candidate = {
      "label" => "2026 Audited Financial Statements",
      "url" => "https://example.ca/uploads/2026/financial-statements.pdf",
      "source_page_url" => "https://example.ca/finance"
    }
    text = "Consolidated Financial Statements For the year ended December 31, 2025"

    assert_equal 2025, @scraper.send(:report_year, candidate, text)
  end

  test "keeps Sooke 2021 as a negative control despite its 2022 SOFI filename" do
    candidate = {
      "label" => "View 2021 SOFI Report",
      "url" => "https://media-002-ca.cdn.govstack.com/sooke-012-ca/media/ccmbbakc/2022-sofi-report.pdf",
      "source_page_url" => "https://www.sooke.ca/media-manager/media-pages/plans-and-reports/2021-sofi-report/"
    }
    text = <<~TEXT
      DISTRICT OF SOOKE
      2021 STATEMENT OF FINANCIAL INFORMATION
      For the year ended December 31, 2021
    TEXT

    assert_equal 2021, @scraper.send(:report_year, candidate, text)
  end

  test "extracts French statement fiscal years from PDF text" do
    text = "États financiers consolidés pour l’exercice terminé le 31 décembre 2024"

    assert_equal 2024, @scraper.send(:financial_statement_fiscal_year, text)
  end

  test "discovers client-rendered Catalis document manager PDFs" do
    document = Nokogiri::HTML(<<~HTML)
      <div class="docmanContainer" id="1781" sec="{SECTION}"></div>
    HTML
    payload = {
      "folderId" => 1781,
      "dmfolders" => [],
      "dmfiles" => [
        {
          "fileId" => 72_324,
          "fileName" => "Municipal Financial Statements 2024.pdf",
          "FileTitle" => "2024 Audited Financial Statements",
          "fileType" => "pdf"
        }
      ]
    }
    searched = []
    errors = []

    @scraper.stub(:fetch_text, [ JSON.generate(payload), "https://example.ca/api" ]) do
      candidates = @scraper.send(
        :docman_candidates,
        document,
        "https://example.ca/audited-financial-statements",
        searched,
        errors
      )

      assert_equal "https://example.ca/uploads/dm/72324/Municipal%20Financial%20Statements%202024.pdf",
        candidates.first.fetch("url")
      assert_equal "2024 Audited Financial Statements", candidates.first.fetch("label")
    end
    assert_empty errors
  end

  test "accepts a municipal statement with a trust fund appendix" do
    types = @scraper.send(
      :document_types,
      "Corporation of the Town of Arnprior Consolidated Financial Statements " \
        "Independent Auditor's Report Statement of Financial Position\f" \
        "Trust Funds Independent Auditor's Report Financial Statements",
      {
        "label" => "2024 Town of Arnprior Audited Financial Statements",
        "url" => "https://example.ca/2024-town-financial-statements.pdf"
      }
    )

    assert_includes types, "financial-statements"
  end

  test "accepts the plural possessive auditors report heading" do
    types = @scraper.send(
      :document_types,
      "INDEPENDENT AUDITORS' REPORT Corporation of the Township of Adelaide Metcalfe " \
        "Financial Statements Statement of Financial Position",
      { "label" => "2021 Financial Statements", "url" => "https://example.ca/2021-financial-statements.pdf" }
    )

    assert_includes types, "financial-statements"
  end

  test "accepts a mojibake apostrophe in the auditors report heading" do
    types = @scraper.send(
      :document_types,
      "INDEPENDENT AUDITOR\u0092S REPORT The Corporation of the Town of Amherstburg " \
        "Consolidated Financial Statements Statement of Financial Position",
      { "label" => "2023 Financial Statements", "url" => "https://example.ca/2023-financial-statements.pdf" }
    )

    assert_includes types, "financial-statements"
  end

  test "accepts the independant auditor spelling found in official statements" do
    types = @scraper.send(
      :document_types,
      "INDEPENDANT AUDITOR'S REPORT City of Bathurst Consolidated Financial Statements " \
        "Consolidated Statement of Financial Position",
      { "label" => "2023 Financial Statements", "url" => "https://example.ca/2023-financial-statements.pdf" }
    )

    assert_includes types, "financial-statements"
  end

  test "accepts a legacy auditors report only with audit work and an opinion" do
    candidate = { "label" => "2017 Financial Statements", "url" => "https://example.ca/2017-statements.pdf" }
    evidence = "AUDITORS' REPORT We have audited the accompanying consolidated financial statements " \
      "Consolidated Statement of Financial Position. In our opinion, the statements present fairly."

    assert_includes @scraper.send(:document_types, evidence, candidate), "financial-statements"
    assert_not_includes @scraper.send(
      :document_types,
      "AUDITORS' REPORT Consolidated Financial Statements",
      candidate
    ), "financial-statements"
  end

  test "accepts a sole practitioner's legacy auditor report" do
    candidate = { "label" => "2015 Financial Statements", "url" => "https://example.ca/2015-statements.pdf" }
    evidence = "AUDITOR'S REPORT I have audited the accompanying consolidated financial statements " \
      "Consolidated Statement of Financial Position. In my opinion, the statements present fairly."

    assert_includes @scraper.send(:document_types, evidence, candidate), "financial-statements"
    assert_not_includes @scraper.send(
      :document_types,
      evidence.sub("In my opinion", "In our opinion"),
      candidate
    ), "financial-statements"
  end

  test "accepts OCR pipe pronouns and a sole practitioner's responsibility paragraph" do
    candidate = { "label" => "2011 Financial Statements", "url" => "https://example.ca/2011-statements.pdf" }
    evidence = "AUDITORS' REPORT | have audited the accompanying consolidated financial statements. " \
      "My responsibility is to express an opinion on these consolidated financial statements."

    assert_includes @scraper.send(:document_types, evidence, candidate), "financial-statements"
    assert_not_includes @scraper.send(
      :document_types,
      evidence.sub("My responsibility", "Our responsibility"),
      candidate
    ), "financial-statements"
  end

  test "recognizes only content-addressed archived financial statements as covered" do
    covered = {
      "documents" => [
        {
          "document_type" => "financial-statements",
          "assets" => [
            {
              "content_sha256" => "a" * 64,
              "archive_path" => "sha256/aa/#{'a' * 64}.pdf"
            }
          ]
        }
      ]
    }
    metadata_only = {
      "documents" => [
        {
          "document_type" => "financial-statements",
          "assets" => []
        }
      ]
    }

    assert @scraper.send(:has_archived_financial_statement?, covered)
    assert_not @scraper.send(:has_archived_financial_statement?, metadata_only)
  end

  test "reads a browser-downloaded local PDF candidate without refetching it" do
    Tempfile.create([ "municipal-statement", ".pdf" ]) do |file|
      file.binmode
      file.write("%PDF-local-test")
      file.flush

      bytes, resolved_url, content_type = @scraper.send(
        :fetch_candidate_binary,
        {
          "url" => "https://government.example/statement.pdf",
          "local_path" => file.path
        }
      )

      assert_equal "%PDF-local-test", bytes
      assert_equal "https://government.example/statement.pdf", resolved_url
      assert_equal "application/pdf", content_type
    end
  end

  test "unwraps DuckDuckGo result links before applying the official-domain filter" do
    body = <<~HTML
      <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.ca%2F2024-financial-statements.pdf&amp;rut=abc">
        2024 Financial Statements
      </a>
      <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Funrelated.ca%2F2024-financial-statements.pdf&amp;rut=def">
        Unrelated result
      </a>
    HTML

    rows = @scraper.send(
      :extract_web_search_candidates,
      body,
      "https://html.duckduckgo.com/html/?q=site%3Aexample.ca",
      "example.ca"
    )

    assert_equal [ "https://example.ca/2024-financial-statements.pdf" ], rows.map { _1.fetch("url") }
  end

  test "unwraps Yahoo result links before applying the official-domain filter" do
    body = <<~HTML
      <a href="https://r.search.yahoo.com/_ylt=test/RU=https%3A%2F%2Fexample.ca%2F2024-financial-statements.pdf/RK=2/RS=test">
        2024 Financial Statements
      </a>
    HTML

    rows = @scraper.send(
      :extract_web_search_candidates,
      body,
      "https://search.yahoo.com/search?p=site%3Aexample.ca",
      "example.ca"
    )

    assert_equal [ "https://example.ca/2024-financial-statements.pdf" ], rows.map { _1.fetch("url") }
  end

  test "allows recognized municipal portals only when trusted portal search is enabled" do
    body = <<~HTML
      <a href="https://pub-example.escribemeetings.com/filestream.ashx?DocumentId=123">
        2024 Audited Financial Statements.pdf
      </a>
    HTML
    search_url = "https://search.yahoo.com/search?p=example"

    assert_empty @scraper.send(:extract_web_search_candidates, body, search_url, "example.ca")
    assert_equal 1, @scraper.send(
      :extract_web_search_candidates,
      body,
      search_url,
      "example.ca",
      allow_trusted_portals: true
    ).size
  end

  test "non-http links without a URI path do not abort page discovery" do
    assert_not @scraper.send(:likely_pdf_url?, "mailto:clerk@example.ca")
    assert_not @scraper.send(:likely_pdf_url?, "mailtoURL:/2024-financial-statements.pdf")
    assert_not @scraper.send(:likely_pdf_url?, "tel:+15555555555")
    assert_not @scraper.send(:likely_pdf_url?, "ftp://example.ca/2024-financial-statements.pdf")
  end

  test "discovers abbreviated statements behind opaque civic document URLs" do
    links = @scraper.send(
      :extract_report_links,
      '<a href="/document/72411">Township of Addington Highlands FS 2024</a>',
      "https://addingtonhighlands.civicweb.net/filepro/documents/35737/",
      report_context: false
    )

    assert_equal 1, links.length
    assert_equal "https://addingtonhighlands.civicweb.net/document/72411", links.sole.fetch("url")
  end

  test "discovers official report links containing literal spaces" do
    links = @scraper.send(
      :extract_report_links,
      '<a href="https://files.example.ca/2023-Final FS-Town of Gillam.pdf">2023 Audited Financials</a>',
      "https://www.example.ca/finance",
      report_context: true
    )

    assert_equal 1, links.length
    assert_equal(
      "https://files.example.ca/2023-Final%20FS-Town%20of%20Gillam.pdf",
      links.sole.fetch("url")
    )
  end

  test "recognizes Catalis downloads as opaque document URLs" do
    assert @scraper.send(
      :opaque_document_url?,
      "https://www.eaststpaul.com/Home/DownloadDocument?docId=0d5e72a7-7ace-4925-b43b-4ad1070c854d"
    )
    assert_not @scraper.send(:opaque_document_url?, "https://www.eaststpaul.com/p/finance-documents")
  end

  test "discovers numeric public download endpoints on a financial statement page" do
    links = @scraper.send(
      :extract_report_links,
      '<a href="/public/download/files/316872">2015</a>',
      "https://www.stephenville.ca/town-hall/audited-financial-statements",
      report_context: true
    )

    assert_equal 1, links.length
    assert_equal "https://www.stephenville.ca/public/download/files/316872", links.sole.fetch("url")
  end

  test "queues AJAX document folders used by Catalis municipal websites" do
    document = Nokogiri::HTML(<<~HTML)
      <a id="main-dir-id" data-directory="root-id">Main folder</a>
      <ul class="directory-list">
        <li data-directory="audit-id"><button>Audited Financial Statements</button></li>
      </ul>
    HTML
    queue = []
    queued = Set.new
    visited = Set.new

    @scraper.send(
      :enqueue_municipal_websites_document_folders,
      document,
      "https://www.pembina.ca/p/files-documents",
      queue,
      queued,
      visited
    )

    assert_equal 2, queue.length
    audit_url, supplied_body, evidence = queue.last
    assert_nil supplied_body
    assert_equal "Audited Financial Statements", evidence
    assert_equal(
      "https://www.pembina.ca/Home/Documents?dirId=audit-id&mainDirId=root-id",
      audit_url
    )
  end

  test "institution-name search validates only the opening eight PDF pages" do
    candidate = { "web_search_scope" => "institution-name" }
    pages = (1..10).map { |page| "page #{page}" }.join("\f")

    validation_text = @scraper.send(:candidate_validation_text, pages, candidate)

    assert_equal (1..8).map { |page| "page #{page}" }.join("\f"), validation_text
  end

  test "off-domain institution-name results must identify the province" do
    row = {
      "canonical_id" => "ca/mb/thompson-city",
      "official_name" => "Thompson, City of",
      "website_url" => "https://www.thompson.ca"
    }
    candidate = {
      "url" => "https://www.nd.gov/auditor/thompson.pdf",
      "web_search_scope" => "institution-name",
      "web_search_result_host" => "nd.gov"
    }

    error = assert_raises(RuntimeError) do
      @scraper.send(:validate_institution_name_search_province!, row, candidate, "City of Thompson, North Dakota")
    end
    assert_includes error.message, "did not identify manitoba"
    assert_nothing_raised do
      @scraper.send(
        :validate_institution_name_search_province!,
        row,
        candidate,
        "City of Thompson, Manitoba"
      )
    end

    official_candidate = candidate.merge(
      "url" => "https://www.thompson.ca/financial-statements.pdf",
      "web_search_result_host" => "www.thompson.ca"
    )
    assert_nothing_raised do
      @scraper.send(:validate_institution_name_search_province!, row, official_candidate, "City of Thompson")
    end
  end

  test "institution-name report evidence must be close to the institution name" do
    assert @scraper.send(
      :institution_report_proximity?,
      "Municipality of Lorne Consolidated Financial Statements",
      "Lorne"
    )
    assert_not @scraper.send(
      :institution_report_proximity?,
      "Municipality of La Broquerie #{'committee discussion ' * 20} audited financial statements",
      "La Broquerie"
    )
  end

  test "opaque archive PDF discovery is explicit and still excludes obvious non-report documents" do
    assert_not @scraper.send(:archive_pdf_candidate?, "https://example.ca/document/72411.pdf")

    opaque_scraper = MunicipalFinancialReportScraper.new(
      manifest_path: "/tmp/not-read.json",
      output_dir: "/tmp/not-written",
      retrieved_at: "2026-08-24T00:00:00Z",
      include_opaque_archive_pdfs: true
    )

    assert opaque_scraper.send(:archive_pdf_candidate?, "https://example.ca/document/72411.pdf")
    assert_not opaque_scraper.send(:archive_pdf_candidate?, "https://example.ca/budget-2024.pdf")
  end

  test "archive discovery prioritizes report-like URLs before opaque PDFs" do
    candidates = [
      { "label" => "72411.pdf", "url" => "https://example.ca/document/72411.pdf" },
      { "label" => "financial-statements-2024.pdf", "url" => "https://example.ca/financial-statements-2024.pdf" }
    ]

    prioritized = @scraper.send(:prioritize_archive_candidates, candidates)

    assert_equal "financial-statements-2024.pdf", prioritized.first.fetch("label")
  end

  test "recognizes only allowlisted third-party municipal document portals" do
    assert @scraper.send(:trusted_document_portal_host?, "addingtonhighlands.civicweb.net")
    assert @scraper.send(:trusted_document_portal_host?, "pub-town.escribemeetings.com")
    assert_not @scraper.send(:trusted_document_portal_host?, "civicweb.net.attacker.example")
    assert_not @scraper.send(:trusted_document_portal_host?, "facebook.com")
  end

  test "bounded deep traversal permits official subdomains" do
    assert @scraper.send(:same_site_host?, "www5.moncton.ca", "moncton.ca")
    assert @scraper.send(:same_site_host?, "documents.town.example", "town.example")
    assert_not @scraper.send(:same_site_host?, "moncton.ca.attacker.example", "moncton.ca")
  end

  test "meeting and agenda pages are eligible for bounded deep traversal" do
    assert @scraper.send(:deep_page?, "Council Meeting Documents")
    assert @scraper.send(:deep_page?, "Agenda packages")
    assert_not @scraper.send(:deep_page?, "Events calendar")
  end

  test "web search discovery accepts only official-domain PDFs" do
    body = <<~HTML
      <a href="https://town.example.ca/files/2024-audited-statements.pdf">2024 audited financial statements</a>
      <a href="https://documents.town.example.ca/opaque/72411.pdf">Audited statements</a>
      <a href="https://attacker.example/2024-audited-statements.pdf">Spoofed result</a>
      <a href="https://town.example.ca/files/budget-2024.pdf">2024 budget</a>
      <a href="https://town.example.ca/finance">Finance page</a>
    HTML

    candidates = @scraper.send(
      :extract_web_search_candidates,
      body,
      "https://search.brave.com/search?q=site%3Atown.example.ca",
      "town.example.ca"
    )

    assert_equal 2, candidates.length
    assert_equal [
      "https://town.example.ca/files/2024-audited-statements.pdf",
      "https://documents.town.example.ca/opaque/72411.pdf"
    ], candidates.pluck("url")
  end

  test "prior crawl revalidation extracts only PDF candidate failures" do
    Tempfile.create([ "municipal-crawl-audit", ".json" ]) do |file|
      file.write(JSON.generate(
        "candidate_errors" => [
          "https://town.example.ca/2024-statements.pdf: PDF did not validate as a financial statement",
          "https://town.example.ca/finance: response is not a PDF (text/html)",
          "https://town.example.ca/budget.pdf: PDF did not validate as a financial statement"
        ]
      ))
      file.flush

      candidates = @scraper.send(
        :prior_audit_candidates,
        Pathname(file.path),
        "https://town.example.ca"
      )

      assert_equal [
        "https://town.example.ca/2024-statements.pdf"
      ], candidates.pluck("url")
    end
  end

  test "does not classify an OPP detachment board annual report as municipal" do
    types = @scraper.send(
      :document_types,
      "South West Dufferin OPP Detachment Board Annual Report, including Amaranth representatives",
      { "label" => "2024 Annual Report", "url" => "https://example.ca/2024-annual-report.pdf" }
    )

    assert_not_includes types, "annual-report"
  end

  test "retries only transient candidate download failures" do
    assert @scraper.send(:transient_candidate_error?, StandardError.new("HTTP 429"))
    assert @scraper.send(:transient_candidate_error?, StandardError.new("Connection refused"))
    assert_not @scraper.send(:transient_candidate_error?, StandardError.new("HTTP 404"))
    assert_not @scraper.send(:transient_candidate_error?, StandardError.new("PDF did not validate"))
  end

  test "candidate OCR reaches an audit opinion after a five-page cover package" do
    calls = []
    ocr = lambda do |_bytes, **options|
      calls << options
      "Independent Auditor's Report for the consolidated financial statements"
    end

    result = @scraper.stub(:pdf_page_count, 40) do
      @scraper.stub(:ocr_pdf_text, ocr) do
        @scraper.send(:expanded_candidate_ocr_text, "%PDF-scanned", "municipal cover pages")
      end
    end

    assert_equal [ { first_page: 6, last_page: 10, allow_empty: true } ], calls
    assert_includes result, "municipal cover pages"
    assert_includes result, "Independent Auditor's Report"
  end

  test "report link extraction ignores opaque contact links" do
    html = <<~HTML
      <a href="mailtoURL:135%20Main%20Street%20Champion,%20AB%20T0L%200R0">Address</a>
      <a href="/2024-audited-financial-statements.pdf">2024 Audited Financial Statements</a>
    HTML

    candidates = @scraper.send(
      :extract_report_links,
      html,
      "https://village.example.ca/financial-statements",
      report_context: true
    )

    assert_equal [ "https://village.example.ca/2024-audited-financial-statements.pdf" ],
      candidates.pluck("url")
  end

  test "retains response cookies for later requests to the same host" do
    response = Struct.new(:cookies) do
      def get_fields(name)
        name == "set-cookie" ? cookies : nil
      end
    end.new([ "session=abc123; HttpOnly; Path=/", "affinity=node7; Secure; Path=/" ])

    @scraper.send(:store_response_cookies, "documents.example.ca", response)

    assert_equal "session=abc123; affinity=node7", @scraper.send(:cookies_for, "documents.example.ca")
    assert_empty @scraper.send(:cookies_for, "other.example.ca")
  end

  test "stops streaming as soon as a response exceeds its byte cap" do
    yielded_chunks = 0
    response = streaming_response(Net::HTTPOK, [ "abcd", "efgh", "ignored" ]) do
      yielded_chunks += 1
    end

    error = stub_http_responses(response) do
      assert_raises(RuntimeError) do
        @scraper.send(:fetch_binary, "https://example.ca/large", max_bytes: 5)
      end
    end

    assert_equal "response exceeded 5 bytes", error.message
    assert_equal 2, yielded_chunks
  end

  test "rejects an oversized content length before reading the response body" do
    yielded_chunks = 0
    response = streaming_response(
      Net::HTTPOK,
      [ "ignored" ],
      "content-length" => "6"
    ) { yielded_chunks += 1 }

    error = stub_http_responses(response) do
      assert_raises(RuntimeError) do
        @scraper.send(:fetch_binary, "https://example.ca/large", max_bytes: 5)
      end
    end

    assert_equal "response exceeded 5 bytes", error.message
    assert_equal 0, yielded_chunks
  end

  test "enforces one wall clock deadline across redirects" do
    redirect = streaming_response(Net::HTTPFound, [ "redirecting" ], "location" => "/final")
    success = streaming_response(Net::HTTPOK, [ "too late" ])
    clock = [ 0.0, 0.25, 1.01 ]

    error = @scraper.stub(:monotonic_now, -> { clock.shift || 1.01 }) do
      stub_http_responses(redirect, success) do
        assert_raises(MunicipalFinancialReportScraper::RequestDeadlineExceeded) do
          @scraper.send(
            :fetch_binary,
            "https://example.ca/start",
            max_bytes: 100,
            deadline: 1.0
          )
        end
      end
    end

    assert_match(/request deadline exceeded/, error.message)
  end

  test "enforces the wall clock deadline while a response keeps trickling" do
    yielded_chunks = 0
    response = streaming_response(Net::HTTPOK, [ "first", "second", "ignored" ]) do
      yielded_chunks += 1
    end
    clock = [ 0.0, 0.4, 1.01 ]

    error = @scraper.stub(:monotonic_now, -> { clock.shift || 1.01 }) do
      stub_http_responses(response) do
        assert_raises(MunicipalFinancialReportScraper::RequestDeadlineExceeded) do
          @scraper.send(
            :fetch_binary,
            "https://example.ca/trickle",
            max_bytes: 100,
            deadline: 1.0
          )
        end
      end
    end

    assert_match(/request deadline exceeded/, error.message)
    assert_equal 2, yielded_chunks
  end

  test "retries an archive index within the original request deadline" do
    deadlines = []
    attempts = 0
    fetcher = lambda do |_url, **options|
      deadlines << options.fetch(:deadline)
      attempts += 1
      raise "HTTP 503" if attempts == 1

      [ "[]", "https://web.archive.org/index" ]
    end

    @scraper.stub(:new_request_deadline, 123.0) do
      @scraper.stub(:throttle_wayback, nil) do
        @scraper.stub(:sleep_with_deadline, nil) do
          @scraper.stub(:fetch_text, fetcher) do
            assert_equal "[]", @scraper.send(:fetch_wayback_index, "https://web.archive.org/index")
          end
        end
      end
    end

    assert_equal [ 123.0, 123.0 ], deadlines
  end

  test "terminates a subprocess that exceeds its deadline" do
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    error = assert_raises(MunicipalFinancialReportScraper::SubprocessDeadlineExceeded) do
      @scraper.send(
        :capture3_with_timeout,
        Gem.ruby,
        "-e",
        "sleep 5",
        timeout_seconds: 0.05
      )
    end

    assert_match(/subprocess deadline exceeded/, error.message)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at, :<, 2
  end

  private

  def streaming_response(response_class, chunks, headers = {}, &on_chunk)
    code, message = response_class <= Net::HTTPRedirection ? [ "302", "Found" ] : [ "200", "OK" ]
    response = response_class.new("1.1", code, message)
    headers.each { |name, value| response[name] = value }
    response.define_singleton_method(:read_body) do |&consumer|
      chunks.each do |chunk|
        on_chunk&.call
        consumer.call(chunk)
      end
    end
    response
  end

  def stub_http_responses(*responses, &)
    requests = 0
    starter = lambda do |*_arguments, **_options, &request_block|
      response = responses.fetch(requests)
      requests += 1
      http = Object.new
      http.define_singleton_method(:request) { |_request, &response_block| response_block.call(response) }
      request_block.call(http)
    end
    Net::HTTP.stub(:start, starter, &)
  end
end
