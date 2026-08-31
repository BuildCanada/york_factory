#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "open3"
require "optparse"
require "pathname"
require "set"
require "stringio"
require "thread"
require "time"
require "timeout"
require "tmpdir"
require "uri"
require "zlib"

class MunicipalFinancialReportScraper
  class RequestDeadlineExceeded < Timeout::Error; end
  class SubprocessDeadlineExceeded < Timeout::Error; end

  USER_AGENT = "YorkFactory public-government-data crawler; contact data@buildcanada.com"
  WEB_SEARCH_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
    "AppleWebKit/537.36 Chrome/140 Safari/537.36"
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  TESSDATA_DIR = Pathname("/Volumes/floppy/york_factory/ocr/tessdata")
  REPORT_PATTERN = /(?:audited?[\s_-]*financial|financial[\s_-]*(?:audit|statements?)|consolidated[\s_-]*financial|annual[\s_-]*(?:municipal[\s_-]*)?reports?|statement[\s_-]*of[\s_-]*financial[\s_-]*information|\bsofi\b|\bfs\b|finance[\s_-]*(?:and[\s_-]*)?(?:reports?|documents?)|proactive[\s_-]*disclosures?|[ée]tats?[\s_-]*financiers?|informations?[\s_-]*financi[èe]res?|rapports?[\s_-]*(?:financiers?|annuels?))/i
  EXCLUDE_PATTERN = /(?:budget|budg[ée]taire|financial[\s_-]*plan|plan[\s_-]*financier|quarterly|trimestriel|interim|grant|subvention|policy|politique|template|gabarit|guide|agenda|ordre[\s_-]*du[\s_-]*jour|minutes|proc[èe]s[\s_-]*verbal|water[\s_-]*quality|drinking[\s_-]*water|eau[\s_-]*potable|salar(?:y|ies)|salaires?|remuneration|r[ée]mun[ée]ration|payment[\s_-]*vouchers?|election[\s_-]*(?:candidate|contribution)|form[\s_-]*4)/i
  HARD_EXCLUDE_PATTERN = /(?:(?<![[:alnum:]])(?:candidate|campaign|unaudited)(?![[:alnum:]])|non[\s_-]*audit[ée]s?|election[\s_-]*(?:candidate|contribution)|form[\s_-]*4)/i
  STRONG_FINANCIAL_LOCATOR_PATTERN = /(?:audited?[\s_-]*financial|consolidated[\s_-]*financial|financial[\s_-]*statements?|[ée]tats?[\s_-]*financiers?)/i
  NON_CORPORATE_ANNUAL_PATTERN = /(?:accessibility|cemetery|credit[\s_-]*rating|economic[\s_-]*(?:review|outlook)|forest|health|housing|library|long[\s_-]*term[\s_-]*care|museum|opp|polic(?:e|ing)|procurement|quality[\s_-]*initiative|terms[\s_-]*of[\s_-]*reference|tourism|transit|trust[\s_-]*fund|wastewater|water|fire|climate)[^\n]{0,200}annual[\s_-]*(?:progress[\s_-]*)?report|annual[\s_-]*(?:progress[\s_-]*)?report[^\n]{0,200}(?:accessibility|cemetery|credit[\s_-]*rating|economic|forest|health|housing|library|long[\s_-]*term[\s_-]*care|museum|opp|polic(?:e|ing)|procurement|quality[\s_-]*initiative|terms[\s_-]*of[\s_-]*reference|tourism|transit|trust[\s_-]*fund|wastewater|water|fire|climate)/i
  PROGRAM_REPORT_PATTERN = /(?:\bccbf\b|\bstp\b|accessibility[\s_-]*(?:advisory|plan)|annual[\s_-]*report[\s_-]*(?:on|of)[\s_-]*building[\s_-]*fees|board[\s_-]*of[\s_-]*health|fraud[\s_-]*and[\s_-]*waste|integrity[\s_-]*commissioner|lobbyist[\s_-]*registrar|municipal[\s_-]*(?:heritage|accessibility)[\s_-]*(?:advisory[\s_-]*)?committee|public[\s_-]*health[\s_-]*(?:services?[\s_-]*)?annual|quality[\s_-]*initiative|sewage[\s_-]*treatment|trust[\s_-]*fund|wastewater[\s_-]*(?:collection|treatment)|lagoon[\s_-]*annual|county[\s_-]*forest[\s_-]*annual)/i
  SUBSIDIARY_FINANCIAL_PATTERN = /(?:(?:cemetery|trust[\s_-]*fund|police[\s_-]*(?:services?|board)|public[\s_-]*library|waterworks)[\s\S]{0,240}financial[\s_-]*statements?|financial[\s_-]*statements?[\s\S]{0,240}(?:cemetery|trust[\s_-]*fund|police[\s_-]*(?:services?|board)|public[\s_-]*library|waterworks)|trust[\s_-]*(?:fund[\s_-]*)?(?:(?:financial[\s_-]*)?statements?|\bfs\b)|(?:arrondissement|caisse[\s_-]*commune|commission[\s_-]*du[\s_-]*r[ée]gime|office[\s_-]*municipal[\s_-]*d['’]habitation|r[ée]gime[\s_-]*de[\s_-]*retraite)[\s\S]{0,1500}(?:[ée]tats?[\s_-]*financiers?|rapport[\s_-]*financier)|(?:[ée]tats?[\s_-]*financiers?|rapport[\s_-]*financier)[\s\S]{0,1500}(?:arrondissement|caisse[\s_-]*commune|commission[\s_-]*du[\s_-]*r[ée]gime|office[\s_-]*municipal[\s_-]*d['’]habitation|r[ée]gime[\s_-]*de[\s_-]*retraite))/i
  NON_MUNICIPAL_ENTITY_PATTERN = /\b(?:candidate|campaign|election|registered[\s_-]*third[\s_-]*party|form[\s_-]*4|arena|community[\s_-]*(?:centre|center)|fire[\s_-]*department|recreation[\s_-]*(?:board|commission)|business[\s_-]*improvement[\s_-]*area)\b/i
  NON_MUNICIPAL_FINANCIAL_PATTERN = /(?:#{NON_MUNICIPAL_ENTITY_PATTERN})[\s\S]{0,1500}(?:financial[\s_-]*statements?|statement[\s_-]*of[\s_-]*financial)|(?:financial[\s_-]*statements?|statement[\s_-]*of[\s_-]*financial)[\s\S]{0,1500}(?:#{NON_MUNICIPAL_ENTITY_PATTERN})/i
  FINANCIAL_HIGHLIGHTS_PATTERN = /(?:faits?[\s_-]*saillants?[\s_-]*(?:du|des)[\s_-]*rapport[\s_-]*financier|rapport[\s_-]*(?:du|de[\s_-]*la)[\s_-]*(?:mairesse?|maire)[\s_-]*sur[\s_-]*la[\s_-]*situation[\s_-]*financi.{0,2}re)/i
  PDF_PATTERN = /\.pdf(?:\?|#|\z)/i
  OPAQUE_DOCUMENT_URL_PATTERN = %r{(?:/(?:Home|Documents)/DownloadDocument\b|/download/dms\b|/public/download/files/\d+\b|filestream\.ashx\b|[?&](?:doc(?:ument)?Id|objectId)=)}i
  YEAR_PATTERN = /(?<!\d)(19[89]\d|20\d{2})(?!\d)/
  SITEMAP_LOC_PATTERN = %r{<loc>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</loc>}im
  COMMON_REPORT_PATHS = %w[
    /financial-statements /audited-financial-statements /annual-report /annual-reports
    /financial-reports /finance /government/finance /town-hall/finance
    /city-hall/finance /municipal-hall/finance /administration/finance
    /p/audited-financial-statements /p/budget-financial /p/documents--application-forms
    /p/downloads-and-documents
    /p/finance /p/finance-and-tax-information /p/financial-information /p/financials
    /p/financial-statements
    /p/municipal-files-documents /p/tax-information
    /index.php/government/financial-info
    /documents/financial-statements /publications/financial-statements
    /etats-financiers /rapports-financiers /rapport-financier /rapport-annuel
    /rapports-annuels /finances /administration/finances /documents-financiers
    /reddition-de-comptes /transparence
  ].freeze
  DEEP_PAGE_PATTERN = /(?:administration|agenda|archive|council|document|download|finance|financial|governance|government|media|meeting|municipal|publication|report|resource|town[s_-]*hall|transparency|uploads?)/i
  DEEP_PAGE_EXCLUDE_PATTERN = /(?:calendar|event|login|logout|register|search|shop|cart|checkout|privacy|accessibility|contact|career|employment|news(?:letter)?|facebook|instagram|linkedin|twitter|youtube)/i
  TRUSTED_DOCUMENT_PORTAL_HOST_PATTERN = /(?:\A|\.)(?:civicweb\.net|escribemeetings\.com|meetingportal\.ca|civicclerk\.com)\z/i
  STOP_TOKENS = Set.new(%w[
    and canton city comte community corporation counties county de des district du government
    harbour la le local l mrc municipal municipale municipalite municipality
    of paroisse region regional regionale rural the town township ville village
  ]).freeze
  # The Common Crawl index currently refuses TLS connections from some networks,
  # while its read-only HTTP endpoint remains available. Capture payloads are
  # still fetched from data.commoncrawl.org over HTTPS and content-validated.
  COMMON_CRAWL_COLLECTIONS_URL = "http://index.commoncrawl.org/collinfo.json"
  COMMON_CRAWL_DATA_ROOT = "https://data.commoncrawl.org"
  HTTP_OPEN_TIMEOUT = 15
  HTTP_READ_TIMEOUT = 60
  HTTP_REQUEST_TIMEOUT = 120
  SUBPROCESS_TIMEOUT = 180
  VALIDATION_TEXT_BYTES = 200_000
  TESSERACT_ENV = { "OMP_THREAD_LIMIT" => "1", "OMP_NUM_THREADS" => "1" }.freeze
  OCR_ORIENTATION_TERMS = /\b(?:annual|audit(?:ed|or|ors)?|city|consolidated|county|district|financial|municipal(?:ity)?|report|statement|town|village|exercice|financi(?:er|ers|ere|eres)|municipalite|rapport|ville)\b/i
  OCR_ORIENTATION_SCORE_THRESHOLD = 12
  BRAVE_SEARCH_URL = "https://search.brave.com/search"
  DUCKDUCKGO_SEARCH_URL = "https://html.duckduckgo.com/html/"
  YAHOO_SEARCH_URL = "https://search.yahoo.com/search"
  WEB_SEARCH_PROVIDERS = %w[brave duckduckgo yahoo].freeze
  WEB_SEARCH_QUERIES = [
    '"financial statements" filetype:pdf',
    '"financial audit" filetype:pdf',
    '"états financiers" filetype:pdf',
    '"independent auditor" filetype:pdf',
    '"annual report" filetype:pdf',
    '"rapport annuel" filetype:pdf'
  ].freeze
  TRUSTED_PORTAL_SEARCH_QUERIES = [
    '"audited financial statements" filetype:pdf',
    '"independent auditor" filetype:pdf'
  ].freeze
  INSTITUTION_NAME_SEARCH_QUERIES = [
    '"financial statements" filetype:pdf',
    '"independent auditor" filetype:pdf',
    '"financial audit" filetype:pdf'
  ].freeze

  def initialize(manifest_path:, output_dir:, retrieved_at:, threads: 6,
    max_pages: 40, max_documents: 100, asset_root: DEFAULT_ASSET_ROOT, canonical_ids: nil,
    exclude_municipality_types: nil, exclude_canonical_ids: nil, include_wayback: false,
    wayback_only: false, include_common_crawl: false, common_crawl_only: false,
    common_crawl_collections: 8, missing_financial_statements_only: false,
    exclude_website_hosts: nil, deep_crawl: false, include_opaque_archive_pdfs: false,
    include_web_search: false, web_search_only: false, web_search_provider: "brave",
    include_trusted_portal_search: false, trusted_portal_search_only: false,
    institution_name_search_only: false, web_search_query_set: "full", revalidate_candidates_from: nil,
    existing_audits_only: false)
    @manifest_path = Pathname(manifest_path).expand_path
    @output_dir = Pathname(output_dir).expand_path
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @threads = Integer(threads)
    @max_pages = Integer(max_pages)
    @max_documents = Integer(max_documents)
    @asset_root = Pathname(asset_root).expand_path
    @canonical_ids = canonical_ids&.to_set
    @exclude_canonical_ids = exclude_canonical_ids.to_a.to_set
    @exclude_municipality_types = exclude_municipality_types.to_a.to_set
    @exclude_website_hosts = exclude_website_hosts.to_a.map { _1.downcase.sub(/\Awww\./, "") }.to_set
    @include_wayback = include_wayback
    @wayback_only = wayback_only
    @include_common_crawl = include_common_crawl
    @common_crawl_only = common_crawl_only
    @common_crawl_collection_limit = Integer(common_crawl_collections)
    @missing_financial_statements_only = missing_financial_statements_only
    @deep_crawl = deep_crawl
    @include_opaque_archive_pdfs = include_opaque_archive_pdfs
    @include_web_search = include_web_search
    @web_search_only = web_search_only
    @web_search_provider = web_search_provider
    @include_trusted_portal_search = include_trusted_portal_search
    @trusted_portal_search_only = trusted_portal_search_only
    @institution_name_search_only = institution_name_search_only
    @web_search_query_set = web_search_query_set
    raise ArgumentError, "unsupported web search query set: #{@web_search_query_set}" unless %w[full audit].include?(@web_search_query_set)
    raise ArgumentError, "unsupported web search provider: #{@web_search_provider}" unless WEB_SEARCH_PROVIDERS.include?(@web_search_provider)
    @revalidate_candidates_from = revalidate_candidates_from && Pathname(revalidate_candidates_from).expand_path
    @existing_audits_only = existing_audits_only
    @raw_dir = @output_dir.join("raw")
    @mutex = Mutex.new
    @wayback_mutex = Mutex.new
    @wayback_last_request_at = 0.0
    @common_crawl_mutex = Mutex.new
    @common_crawl_last_request_at = 0.0
    @common_crawl_collection_urls = nil
    @web_search_mutex = Mutex.new
    @web_search_last_request_at = 0.0
    @cookie_mutex = Mutex.new
    @cookies_by_host = Hash.new { |hash, host| hash[host] = {} }
  end

  def run
    raise "refusing to overwrite #{@output_dir.join('financial-report-batch.json')}" if @output_dir.join("financial-report-batch.json").exist?

    FileUtils.mkdir_p([ @raw_dir.join("institutions"), @asset_root.join("sha256") ])
    payload = JSON.parse(@manifest_path.read)
    rows = payload.fetch("municipalities").select { |row| row["website_url"].to_s.match?(%r{\Ahttps?://}) }
    rows.reject! { |row| has_archived_financial_statement?(row) } if @missing_financial_statements_only
    rows.select! { |row| @canonical_ids.include?(row.fetch("canonical_id")) } if @canonical_ids
    rows.reject! { |row| @exclude_canonical_ids.include?(row.fetch("canonical_id")) }
    rows.reject! { |row| @exclude_municipality_types.include?(row["municipality_type"]) }
    rows.reject! { |row| @exclude_website_hosts.include?(website_host(row["website_url"])) }
    rows.select! { |row| institution_audit_path(row).exist? } if @existing_audits_only
    results = parallel_map(rows) do |row|
      path = institution_audit_path(row)
      path.exist? ? JSON.parse(path.read) : scrape_institution(row)
    end
    write_batch(payload, rows, results)
  end

  private

  def has_archived_financial_statement?(row)
    Array(row["documents"]).any? do |document|
      document["document_type"] == "financial-statements" && Array(document["assets"]).any? do |asset|
        asset["content_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) && asset["archive_path"].to_s.match?(/\S/)
      end
    end
  end

  def scrape_institution(row)
    pages, candidates, searched, discovery_errors = discover_reports(row)
    pages.first(@max_pages).each do |page_url|
      body, resolved_url = fetch_text(page_url)
      searched << resolved_url
      candidates.concat(extract_report_links(body, resolved_url, report_context: report_context?(page_url, body)))
    rescue StandardError => error
      discovery_errors << "#{page_url}: #{error.message}"
    end

    candidates.uniq! { |candidate| normalized_url(candidate.fetch("url")) }
    candidate_count = candidates.length
    candidate_errors = []
    reports = candidates.first(@max_documents).flat_map do |candidate|
      verify_and_archive(row, candidate)
    rescue StandardError => error
      candidate_errors << "#{candidate.fetch('url')}: #{error.message}"
      []
    end
    reports.uniq! { |report| [ report.fetch("document_type"), report.fetch("year"), report.fetch("content_sha256") ] }
    reports.sort_by! { |report| [ report.fetch("document_type"), report.fetch("year"), report.fetch("download_url") ] }

    result = {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => official_name(row),
      "website_url" => row.fetch("website_url"),
      "searched_locations" => searched.uniq.sort,
      "candidate_count" => candidate_count,
      "validated_report_count" => reports.length,
      "reports" => reports,
      "gaps" => gaps(candidate_count, reports, discovery_errors, candidate_errors),
      "discovery_errors" => discovery_errors,
      "candidate_errors" => candidate_errors
    }
    write_institution_audit(row, result)
    result
  rescue StandardError => error
    result = {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => official_name(row),
      "website_url" => row.fetch("website_url"),
      "searched_locations" => [],
      "candidate_count" => 0,
      "validated_report_count" => 0,
      "reports" => [],
      "gaps" => [ "Institution crawl failed: #{error.message}" ],
      "discovery_errors" => [ "#{error.class}: #{error.message}" ],
      "candidate_errors" => []
    }
    write_institution_audit(row, result)
    result
  end

  def discover_reports(row)
    website = row.fetch("website_url")
    if @revalidate_candidates_from
      audit_path = prior_institution_audit_path(row)
      return [ [], prior_audit_candidates(audit_path, website), [ audit_path.to_s ], [] ]
    end

    if @web_search_only
      candidates, searched, errors = web_search_candidates(row)
      return [ [], candidates, searched, errors ]
    end

    if @common_crawl_only
      candidates = common_crawl_candidates(website)
      searched = candidates.map { |row| row.fetch("common_crawl_index_url") }.uniq
      return [ [], candidates, searched, [] ]
    end

    if @wayback_only
      return [ [], wayback_candidates(website), [ wayback_index_url(website) ], [] ]
    end

    root = site_root(website)
    searched = []
    errors = []
    begin
      root_body, resolved_root = fetch_text(root)
      root = site_root(resolved_root)
      searched << resolved_root
    rescue StandardError => error
      return [ [], [], searched, [ "official website root: #{error.message}" ] ]
    end
    root_links = extract_report_links(root_body, resolved_root, report_context: report_context?(resolved_root, root_body))
    sitemap_urls = Set.new
    begin
      robots_url = URI.join(root, "/robots.txt").to_s
      robots, resolved_url = fetch_text(robots_url)
      searched << resolved_url
      robots.scan(/^Sitemap:\s*(\S+)/i) { |match| sitemap_urls << match.first }
    rescue StandardError => error
      errors << "robots.txt: #{error.message}"
    end
    %w[/sitemap.xml /sitemap_index.xml /wp-sitemap.xml].each do |path|
      sitemap_urls << URI.join(root, path).to_s
    end

    all_urls = Set.new
    sitemap_urls.to_a.first(10).each do |url|
      collect_sitemap_urls(url, all_urls, searched, errors, depth: 0)
    end

    pages = root_links.reject { |link| likely_pdf_url?(link.fetch("url")) }.map { |link| link.fetch("url") }
    candidates = root_links.select { |link| likely_pdf_url?(link.fetch("url")) }
    all_urls.each do |url|
      evidence = CGI.unescape(url)
      next unless evidence.match?(REPORT_PATTERN)
      next if excluded_report_evidence?(evidence)

      if likely_pdf_url?(url)
        candidates << candidate(url, File.basename(URI(url).path), url)
      else
        pages << url
      end
    rescue URI::InvalidURIError
      next
    end

    if @include_wayback
      wayback_candidates(website).each { |row| candidates << row }
    end
    if @include_common_crawl
      common_crawl_candidates(website).each { |row| candidates << row }
    end
    if @include_web_search
      search_candidates, search_urls, search_errors = web_search_candidates(row)
      candidates.concat(search_candidates)
      searched.concat(search_urls)
      errors.concat(search_errors)
    end

    (COMMON_REPORT_PATHS.map { |path| URI.join(root, path).to_s } + search_paths(root)).uniq.each do |page_url|
      body, resolved_url = fetch_text(page_url)
      searched << resolved_url
      context = report_context?(resolved_url, body)
      links = extract_report_links(body, resolved_url, report_context: context)
      candidates.concat(links.select { |link| likely_pdf_url?(link.fetch("url")) })
      pages.concat(links.reject { |link| likely_pdf_url?(link.fetch("url")) }.map { |link| link.fetch("url") })
      if @deep_crawl && context
        candidates.concat(deep_crawl_candidates(root, resolved_url, body, searched, errors))
      end
    rescue StandardError
      next
    end
    candidates.concat(deep_crawl_candidates(root, resolved_root, root_body, searched, errors)) if @deep_crawl
    [ pages.uniq, candidates, searched, errors ]
  end

  def prior_audit_candidates(path, website)
    audit = JSON.parse(path.read)
    Array(audit["candidate_errors"]).filter_map do |message|
      url = message.partition(": ").first
      next unless likely_pdf_url?(url)
      next if excluded_report_evidence?(CGI.unescape(url))

      candidate(url, CGI.unescape(url_basename(url)), website)
    end.uniq { |row| normalized_url(row.fetch("url")) }
  end

  def prior_institution_audit_path(row)
    @revalidate_candidates_from.join("#{row.fetch('canonical_id').tr('/', '__')}.json")
  end

  def deep_crawl_candidates(root, resolved_root, root_body, searched, errors)
    root_host = website_host(root)
    allowed_hosts = Set[root_host]
    queue = [ [ resolved_root, root_body, resolved_root ] ]
    queued = Set[normalized_url(resolved_root)]
    visited = Set.new
    candidates = []
    until queue.empty? || visited.length >= @max_pages
      begin
        page_url, supplied_body, queued_evidence = queue.shift
        normalized_page = normalized_url(page_url)
        next if visited.include?(normalized_page)

        visited << normalized_page
        if supplied_body
          body = supplied_body
          resolved_url = page_url
          pdf_response = false
        else
          bytes, resolved_url, content_type = fetch_binary(page_url, max_bytes: 150 * 1024 * 1024)
          pdf_response = bytes.start_with?("%PDF-") || content_type.match?(/application\/pdf/i)
          body = bytes.force_encoding("UTF-8").scrub unless pdf_response
        end
        searched << resolved_url
        if pdf_response || likely_pdf_url?(resolved_url)
          evidence = CGI.unescapeHTML("#{queued_evidence} #{page_url} #{resolved_url}")
          if !excluded_report_evidence?(evidence) && evidence.match?(REPORT_PATTERN)
            label = queued_evidence.to_s.gsub(/\s+/, " ").strip
            label = CGI.unescape(url_basename(resolved_url)) if label.empty?
            candidates << candidate(resolved_url, label, page_url)
          end
          next
        end

        report_context = report_context?(resolved_url, body)
        document = Nokogiri::HTML(body)
        candidates.concat(docman_candidates(document, resolved_url, searched, errors))
        enqueue_municipal_websites_document_folders(
          document,
          resolved_url,
          queue,
          queued,
          visited
        )
        document.css("a[href]").each do |anchor|
          href = anchor["href"].to_s.strip
          next if href.empty? || non_web_href?(href)

          absolute = resolve_href(resolved_url, href)
          evidence = CGI.unescapeHTML("#{anchor.text} #{absolute}").gsub(/\s+/, " ").strip
          if opaque_document_url?(absolute) && evidence.match?(REPORT_PATTERN) && !excluded_report_evidence?(evidence)
            candidates << candidate(absolute, anchor.text, resolved_url)
            next
          end
          if likely_pdf_url?(absolute)
            next if excluded_report_evidence?(evidence)
            next unless evidence.match?(REPORT_PATTERN) || (report_context && evidence.match?(YEAR_PATTERN))

            candidates << candidate(absolute, anchor.text, resolved_url)
            next
          end
          target_host = website_host(absolute)
          current_host = website_host(resolved_url)
          if trusted_document_portal_host?(target_host) && allowed_hosts.include?(current_host)
            allowed_hosts << target_host
          end
          next unless allowed_hosts.include?(target_host) || same_site_host?(target_host, root_host)
          portal_page = trusted_document_portal_host?(target_host) && !evidence.match?(DEEP_PAGE_EXCLUDE_PATTERN)
          next unless deep_page?(evidence) || portal_page

          normalized = normalized_url(absolute)
          next if queued.include?(normalized) || visited.include?(normalized)

          queued << normalized
          queue << [ absolute, nil, evidence ]
        rescue URI::Error
          next
        end
      rescue StandardError => error
        errors << "deep crawl #{page_url}: #{error.message}"
      end
    end
    candidates.uniq { normalized_url(_1.fetch("url")) }
  end

  # Newer Catalis sites render document libraries through a JSON API. The page
  # contains only a docman container ID and security token; file links are
  # constructed client-side and therefore never appear in the HTML crawl.
  def docman_candidates(document, page_url, searched, errors)
    document.css(".docmanContainer[id][sec]").flat_map do |container|
      root_folder = container["id"].to_s.strip
      section = container["sec"].to_s.strip
      next [] if root_folder.empty? || section.empty?

      docman_folder_candidates(page_url, root_folder, section, searched, errors)
    end
  end

  def docman_folder_candidates(page_url, root_folder, section, searched, errors)
    queue = [ root_folder ]
    visited = Set.new
    candidates = []
    until queue.empty? || visited.length >= @max_pages || candidates.length >= @max_documents
      folder_id = queue.shift.to_s
      next if visited.include?(folder_id)

      begin
        visited << folder_id
        query = URI.encode_www_form(folderid: folder_id, sec: section)
        api_url = URI.join(page_url, "/admin/dm/Public/GetFolderById/?#{query}").to_s
        body, resolved_url = fetch_text(api_url)
        searched << resolved_url
        payload = JSON.parse(body)
        queue.concat(Array(payload["dmfolders"]).filter_map { |folder| folder["folderId"] })
        Array(payload["dmfiles"]).each do |file|
          label = file["FileTitle"].to_s.strip
          label = file["fileName"].to_s.strip if label.empty?
          next if label.empty? || excluded_report_evidence?(label) || !label.match?(REPORT_PATTERN)
          next unless file["fileType"].to_s.casecmp?("pdf")

          file_name = URI::DEFAULT_PARSER.escape(file.fetch("fileName"))
          file_url = URI.join(page_url, "/uploads/dm/#{file.fetch('fileId')}/#{file_name}").to_s
          candidates << candidate(file_url, label, page_url)
        end
      rescue StandardError => error
        errors << "docman folder #{folder_id}: #{error.message}"
      end
    end
    candidates
  end

  # Catalis Municipal Websites pages render document folders through an AJAX
  # endpoint. The initial page contains only data-directory UUIDs, so ordinary
  # link crawling never sees the statement downloads inside those folders.
  def enqueue_municipal_websites_document_folders(document, page_url, queue, queued, visited)
    main_directory = document.at_css("#main-dir-id[data-directory]")&.[]("data-directory").to_s.strip
    folder_endpoint = if URI(page_url).path == "/Documents/Documents" || document.to_html.include?("/Documents/Documents")
      "/Documents/Documents"
    else
      "/Home/Documents"
    end
    document.css("[data-directory]").each do |element|
      directory = element["data-directory"].to_s.strip
      next if directory.empty?

      query = URI.encode_www_form(dirId: directory, mainDirId: main_directory)
      folder_url = URI.join(page_url, "#{folder_endpoint}?#{query}").to_s
      normalized = normalized_url(folder_url)
      next if queued.include?(normalized) || visited.include?(normalized)

      label = element.text.gsub(/\s+/, " ").strip
      label = "document folder" if label.empty?
      queued << normalized
      queue << [ folder_url, nil, label ]
    rescue URI::InvalidURIError
      next
    end
  end

  def deep_page?(evidence)
    evidence.match?(DEEP_PAGE_PATTERN) && !evidence.match?(DEEP_PAGE_EXCLUDE_PATTERN)
  end

  def trusted_document_portal_host?(host)
    host.to_s.match?(TRUSTED_DOCUMENT_PORTAL_HOST_PATTERN)
  end

  def same_site_host?(candidate_host, root_host)
    candidate_host == root_host || candidate_host.end_with?(".#{root_host}")
  end

  def wayback_candidates(website)
    index_url = wayback_index_url(website)
    body = fetch_wayback_index(index_url)
    rows = JSON.parse(body)
    header = rows.shift
    return [] unless header

    candidates = rows.filter_map do |values|
      row = header.zip(values).to_h
      original = row.fetch("original")
      evidence = CGI.unescape(original)
      next unless archive_pdf_candidate?(evidence)

      snapshot = "https://web.archive.org/web/#{row.fetch('timestamp')}id_/#{original}"
      candidate(snapshot, File.basename(URI(original).path), original).merge(
        "original_url" => original,
        "wayback_timestamp" => row.fetch("timestamp"),
        "wayback_digest" => row["digest"]
      )
    rescue URI::InvalidURIError
      nil
    end
    prioritize_archive_candidates(candidates)
  end

  def fetch_wayback_index(index_url)
    attempts = 0
    deadline = new_request_deadline
    begin
      attempts += 1
      throttle_wayback
      body, = fetch_text(index_url, deadline: deadline)
      body
    rescue StandardError => error
      return "[]" if error.message == "HTTP 404"

      raise if attempts >= 4

      sleep_with_deadline(2**(attempts - 1), deadline, index_url)
      retry
    end
  end

  def throttle_wayback
    @wayback_mutex.synchronize do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep_for = 0.75 - (now - @wayback_last_request_at)
      sleep(sleep_for) if sleep_for.positive?
      @wayback_last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  def wayback_index_url(website)
    host = URI(website).host.to_s.sub(/\Awww\./, "")
    query = URI.encode_www_form(
      url: "#{host}/",
      matchType: "domain",
      output: "json",
      fl: "timestamp,original,statuscode,mimetype,digest",
      filter: [ "statuscode:200", "mimetype:application/pdf" ],
      collapse: "urlkey"
    )
    "https://web.archive.org/cdx/search/cdx?#{query}"
  end

  def common_crawl_candidates(website)
    host = URI(website).host.to_s.sub(/\Awww\./, "")
    candidates = []
    common_crawl_collection_urls.each do |index_url|
      query = URI.encode_www_form(
        url: "#{host}/*",
        matchType: "domain",
        output: "json",
        filter: [ "status:200", "mime:application/pdf" ],
        collapse: "urlkey"
      )
      request_url = "#{index_url}?#{query}"
      body = fetch_common_crawl_index(request_url)
      body.each_line do |line|
        row = JSON.parse(line)
        original = row["url"].to_s
        evidence = CGI.unescape(original)
        next unless archive_pdf_candidate?(evidence)

        candidates << candidate(original, File.basename(URI(original).path), website).merge(
          "common_crawl_index_url" => request_url,
          "common_crawl_timestamp" => row["timestamp"],
          "common_crawl_digest" => row["digest"],
          "common_crawl_filename" => row["filename"],
          "common_crawl_offset" => row["offset"],
          "common_crawl_length" => row["length"]
        )
      rescue JSON::ParserError, URI::InvalidURIError
        next
      end
      break if candidates.length >= @max_documents
    end
    prioritize_archive_candidates(candidates.uniq { |row| normalized_url(row.fetch("url")) })
  end

  def web_search_candidates(row)
    website = row.fetch("website_url")
    host = website_host(website)
    searched = []
    errors = []
    site_queries = if @trusted_portal_search_only || @institution_name_search_only
      []
    elsif @web_search_query_set == "audit"
      [ '"financial audit" filetype:pdf' ]
    else
      WEB_SEARCH_QUERIES
    end
    candidates = site_queries.flat_map do |query|
      search_url = web_search_url("site:#{host} #{query}")
      searched << search_url
      body, resolved_url = fetch_web_search(search_url)
      extract_web_search_candidates(body, resolved_url, host)
    rescue StandardError => error
      errors << "#{search_url}: #{error.message}"
      []
    end
    if @include_trusted_portal_search
      institution_query = %Q("#{official_name(row)}")
      TRUSTED_PORTAL_SEARCH_QUERIES.each do |query|
        search_url = web_search_url("#{institution_query} #{query}")
        searched << search_url
        body, resolved_url = fetch_web_search(search_url)
        candidates.concat(extract_web_search_candidates(body, resolved_url, host, allow_trusted_portals: true))
      rescue StandardError => error
        errors << "#{search_url}: #{error.message}"
      end
    end
    if @institution_name_search_only
      institution_query = %Q("#{institution_search_name(row)}")
      INSTITUTION_NAME_SEARCH_QUERIES.each do |query|
        search_url = web_search_url("#{institution_query} #{query}")
        searched << search_url
        body, resolved_url = fetch_web_search(search_url)
        candidates.concat(extract_web_search_candidates(
          body,
          resolved_url,
          host,
          allow_any_host: true,
          search_scope: "institution-name"
        ))
      rescue StandardError => error
        errors << "#{search_url}: #{error.message}"
      end
    end
    [ candidates.uniq { |row| normalized_url(row.fetch("url")) }, searched, errors ]
  end

  def web_search_url(query)
    case @web_search_provider
    when "brave"
      "#{BRAVE_SEARCH_URL}?#{URI.encode_www_form(q: query, source: "web")}"
    when "duckduckgo"
      "#{DUCKDUCKGO_SEARCH_URL}?#{URI.encode_www_form(q: query)}"
    when "yahoo"
      "#{YAHOO_SEARCH_URL}?#{URI.encode_www_form(p: query)}"
    end
  end

  def fetch_web_search(search_url)
    attempts = 0
    deadline = new_request_deadline
    begin
      attempts += 1
      throttle_web_search
      fetch_text(search_url, user_agent: WEB_SEARCH_USER_AGENT, deadline: deadline)
    rescue StandardError => error
      raise unless error.message.match?(/\AHTTP (?:429|5\d\d)\z/) && attempts < 3

      sleep_with_deadline(15 * attempts, deadline, search_url)
      retry
    end
  end

  def extract_web_search_candidates(body, search_url, official_host, allow_trusted_portals: false,
    allow_any_host: false, search_scope: "official-domain")
    Nokogiri::HTML(body).css("a[href]").filter_map do |anchor|
      url = unwrap_web_search_url(anchor["href"].to_s, search_url)
      next unless url.match?(%r{\Ahttps?://})

      result_host = website_host(url)
      official_result = result_host == official_host || result_host.end_with?(".#{official_host}")
      trusted_portal_result = allow_trusted_portals && result_host.match?(TRUSTED_DOCUMENT_PORTAL_HOST_PATTERN)
      next unless allow_any_host || official_result || trusted_portal_result

      label = anchor.text.gsub(/\s+/, " ").strip
      next unless likely_pdf_url?(url) || (trusted_portal_result && label.match?(PDF_PATTERN))

      evidence = CGI.unescapeHTML("#{label} #{url}")
      next if excluded_report_evidence?(evidence)

      candidate(url, label, search_url).merge(
        "web_search_scope" => search_scope,
        "web_search_result_host" => result_host
      )
    rescue URI::InvalidURIError
      nil
    end
  end

  def institution_search_name(row)
    name = official_name(row)
    prefix = {
      "city" => "City of",
      "municipality" => "Municipality of",
      "rural_municipality" => "Rural Municipality of",
      "town" => "Town of",
      "township" => "Township of",
      "village" => "Village of"
    }[row["municipality_type"]]
    prefix ? "#{prefix} #{name}" : name
  end

  def unwrap_web_search_url(url, search_url)
    absolute_url = URI.join(search_url, url).to_s
    uri = URI(absolute_url)
    if uri.host.to_s.match?(/(?:\A|\.)duckduckgo\.com\z/i)
      return CGI.parse(uri.query.to_s).fetch("uddg", []).first || absolute_url
    end
    if uri.host.to_s.match?(/(?:\A|\.)search\.yahoo\.com\z/i)
      encoded_target = uri.path[%r{/RU=([^/]+)}, 1]
      return CGI.unescape(encoded_target) if encoded_target
    end

    absolute_url
  rescue URI::InvalidURIError
    url
  end

  def throttle_web_search
    @web_search_mutex.synchronize do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      interval = @web_search_provider == "yahoo" ? 1.5 : 5.0
      sleep_for = interval - (now - @web_search_last_request_at)
      sleep(sleep_for) if sleep_for.positive?
      @web_search_last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  def archive_pdf_candidate?(evidence)
    return false if excluded_report_evidence?(evidence)

    @include_opaque_archive_pdfs || evidence.match?(REPORT_PATTERN)
  end

  def prioritize_archive_candidates(candidates)
    candidates.sort_by do |row|
      evidence = CGI.unescape("#{row['label']} #{row['original_url'] || row['url']}")
      [ evidence.match?(REPORT_PATTERN) ? 0 : 1, evidence.match?(YEAR_PATTERN) ? 0 : 1, evidence ]
    end
  end

  def common_crawl_collection_urls
    @common_crawl_mutex.synchronize do
      return @common_crawl_collection_urls if @common_crawl_collection_urls

      attempts = 0
      deadline = new_request_deadline
      begin
        attempts += 1
        body, = fetch_text(COMMON_CRAWL_COLLECTIONS_URL, deadline: deadline)
      rescue StandardError
        raise if attempts >= 4

        sleep_with_deadline(2**(attempts - 1), deadline, COMMON_CRAWL_COLLECTIONS_URL)
        retry
      end
      collections = JSON.parse(body)
      @common_crawl_collection_urls = collections.first(@common_crawl_collection_limit).map do |row|
        row.fetch("cdx-api").sub(%r{\Ahttps://index\.commoncrawl\.org/}, "http://index.commoncrawl.org/")
      end
    end
  end

  def fetch_common_crawl_index(url)
    attempts = 0
    deadline = new_request_deadline
    begin
      attempts += 1
      throttle_common_crawl
      body, = fetch_text(url, max_bytes: 100 * 1024 * 1024, deadline: deadline)
      body.start_with?("{\"message\":") ? "" : body
    rescue StandardError => error
      return "" if error.message == "HTTP 404"

      raise if attempts >= 4

      sleep_with_deadline(2**(attempts - 1), deadline, url)
      retry
    end
  end

  def throttle_common_crawl
    @common_crawl_mutex.synchronize do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep_for = 0.2 - (now - @common_crawl_last_request_at)
      sleep(sleep_for) if sleep_for.positive?
      @common_crawl_last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  def collect_sitemap_urls(url, collected, searched, errors, depth:)
    return if depth > 2 || searched.include?(url)

    body, resolved_url = fetch_text(url, max_bytes: 50 * 1024 * 1024)
    searched << resolved_url
    locations = body.scan(SITEMAP_LOC_PATTERN).flatten.map { |value| CGI.unescapeHTML(value.strip) }.reject(&:empty?)
    if body.match?(/<sitemapindex/i)
      locations.first(50).each do |child|
        collect_sitemap_urls(child, collected, searched, errors, depth: depth + 1)
      end
    else
      locations.first(100_000).each { |location| collected << location }
    end
  rescue StandardError => error
    errors << "#{url}: #{error.message}"
  end

  def extract_report_links(body, base_url, report_context:)
    document = Nokogiri::HTML(body)
    document.css("a[href]").filter_map do |anchor|
      href = anchor["href"].to_s.strip
      next if href.empty? || non_web_href?(href)

      absolute = resolve_href(base_url, href)
      next unless absolute.match?(%r{\Ahttps?://})

      label = anchor.text.gsub(/\s+/, " ").strip
      evidence = CGI.unescapeHTML("#{label} #{absolute}")
      next if excluded_report_evidence?(evidence)
      next unless evidence.match?(REPORT_PATTERN) || (report_context && likely_report_asset?(evidence, absolute))

      candidate(absolute, label, base_url)
    rescue URI::Error
      nil
    end
  end

  def non_web_href?(href)
    href.match?(/\A(?!https?:)[a-z][a-z0-9+.-]*:/i)
  end

  def likely_report_asset?(evidence, url)
    likely_pdf_url?(url) && (evidence.match?(YEAR_PATTERN) || evidence.match?(/financial|annual|audit|statement/i))
  end

  def excluded_report_evidence?(evidence)
    return true if evidence.match?(HARD_EXCLUDE_PATTERN)
    return false unless evidence.match?(EXCLUDE_PATTERN)

    !evidence.match?(STRONG_FINANCIAL_LOCATOR_PATTERN)
  end

  def opaque_document_url?(url)
    url.match?(OPAQUE_DOCUMENT_URL_PATTERN)
  end

  def resolve_href(base_url, href)
    decoded = CGI.unescapeHTML(href.to_s.strip)
    unsafe_without_percent = /[^\-_.!~*'()a-zA-Z\d;\/?::@&=+$,\[\]%]/
    escaped = URI::DEFAULT_PARSER.escape(decoded, unsafe_without_percent)
    URI.join(base_url, escaped).to_s
  end

  def report_context?(url, body)
    CGI.unescape(url).match?(REPORT_PATTERN) || Nokogiri::HTML(body).at_css("title,h1")&.text.to_s.match?(REPORT_PATTERN)
  end

  def candidate(url, label, source_page_url)
    { "url" => url, "label" => label.to_s.strip, "source_page_url" => source_page_url }
  end

  def verify_and_archive(row, candidate_row)
    bytes, resolved_url, content_type = fetch_candidate_binary(candidate_row)
    raise "response is not a PDF (#{content_type})" unless bytes.start_with?("%PDF-")

    text = pdf_text(bytes)
    ocr_text = nil
    validation_text = candidate_validation_text(text, candidate_row)
    unless institution_matches?(validation_text, official_name(row))
      ocr_text = ocr_pdf_text(bytes)
      ocr_validation_text = candidate_validation_text(ocr_text, candidate_row)
      if institution_matches?(ocr_validation_text, official_name(row))
        text = ocr_text
        validation_text = ocr_validation_text
      end
    end
    unless institution_matches?(validation_text, official_name(row))
      raise "PDF opening pages did not identify #{official_name(row)}"
    end
    validate_institution_name_search_report_page!(row, candidate_row, validation_text)
    validate_institution_name_search_province!(row, candidate_row, validation_text)

    evidence = "#{candidate_row.fetch('label')} #{resolved_url} #{safe_byteslice(validation_text, VALIDATION_TEXT_BYTES)}"
    types = document_types(evidence, candidate_row)
    if types.empty?
      ocr_text = expanded_candidate_ocr_text(bytes, ocr_text)
      ocr_validation_text = candidate_validation_text(ocr_text, candidate_row)
      if institution_matches?(ocr_validation_text, official_name(row))
        validate_institution_name_search_report_page!(row, candidate_row, ocr_validation_text)
        validate_institution_name_search_province!(row, candidate_row, ocr_validation_text)
        ocr_evidence = "#{candidate_row.fetch('label')} #{resolved_url} #{safe_byteslice(ocr_validation_text, VALIDATION_TEXT_BYTES)}"
        ocr_types = document_types(ocr_evidence, candidate_row)
        unless ocr_types.empty?
          text = ocr_text
          validation_text = ocr_validation_text
          types = ocr_types
        end
      end
    end
    raise "PDF did not validate as a financial statement, SOFI, or annual report" if types.empty?

    year = report_year(candidate_row, text)
    raise "reporting year could not be determined" unless year

    asset = archive_pdf(bytes)
    languages = source_languages(text)
    types.map do |type|
      asset.merge(
        "document_type" => type,
        "year" => year,
        "title" => report_title(row, candidate_row, type, year, languages),
        "source_page_url" => candidate_row.fetch("source_page_url"),
        "download_url" => candidate_row["original_url"] || resolved_url,
        "languages" => languages,
        "retrieved_at" => @retrieved_at.iso8601,
        "rights_status" => "metadata_only",
        "verification" => {
          "institution_name_in_pdf" => true,
          "document_type_from_pdf_text" => true,
          "pdf_text_sha256" => Digest::SHA256.hexdigest(text),
          "wayback_snapshot_url" => candidate_row["original_url"] ? resolved_url : nil,
          "wayback_timestamp" => candidate_row["wayback_timestamp"],
          "wayback_digest" => candidate_row["wayback_digest"],
          "common_crawl_index_url" => candidate_row["common_crawl_index_url"],
          "common_crawl_timestamp" => candidate_row["common_crawl_timestamp"],
          "common_crawl_digest" => candidate_row["common_crawl_digest"],
          "web_search_scope" => candidate_row["web_search_scope"],
          "web_search_result_host" => candidate_row["web_search_result_host"]
        }
      )
    end
  end

  def expanded_candidate_ocr_text(bytes, opening_ocr_text)
    page_count = pdf_page_count(bytes)
    return ocr_pdf_text(bytes, max_pages: [ page_count, 10 ].min) unless opening_ocr_text
    return opening_ocr_text if page_count <= 5

    last_page = [ page_count, 10 ].min
    later_text = ocr_pdf_text(bytes, first_page: 6, last_page: last_page, allow_empty: true)
    "#{opening_ocr_text}\f#{later_text}"
  end

  def candidate_validation_text(text, candidate_row)
    return text unless candidate_row["web_search_scope"] == "institution-name"

    text.split("\f").first(8).join("\f")
  end

  def validate_institution_name_search_province!(row, candidate_row, text)
    return unless candidate_row["web_search_scope"] == "institution-name"

    result_host_value = candidate_row["web_search_result_host"] || candidate_row.fetch("url")
    result_host = if result_host_value.include?("://")
      website_host(result_host_value)
    else
      result_host_value.downcase.sub(/\Awww\./, "")
    end
    official_host = website_host(row["website_url"])
    return if result_host == official_host || result_host.end_with?(".#{official_host}")

    province = {
      "ab" => "alberta", "bc" => "british columbia", "mb" => "manitoba",
      "nb" => "new brunswick", "nl" => "newfoundland", "ns" => "nova scotia",
      "on" => "ontario", "pe" => "prince edward island", "qc" => "quebec",
      "sk" => "saskatchewan", "nt" => "northwest territories", "nu" => "nunavut",
      "yt" => "yukon"
    }.fetch(row.fetch("canonical_id").split("/").fetch(1))
    return if normalize(text).include?(province)

    raise "off-domain institution-name result did not identify #{province} in its opening pages"
  end

  def validate_institution_name_search_report_page!(row, candidate_row, text)
    return unless candidate_row["web_search_scope"] == "institution-name"

    matching_page = text.split("\f").any? do |page|
      institution_report_proximity?(page, official_name(row))
    end
    return if matching_page

    raise "institution-name result did not place the institution and report title on the same opening page"
  end

  def institution_report_proximity?(page, name)
    normalized_page = normalize(page)
    normalized_name = normalize(name)
    core_name = normalized_name.split.reject { |token| STOP_TOKENS.include?(token) }.join(" ")
    return false if core_name.empty?

    name_positions = normalized_page.enum_for(:scan, /\b#{Regexp.escape(core_name)}\b/).map { Regexp.last_match.begin(0) }
    report_positions = normalized_page.enum_for(
      :scan,
      /(?:financial statements?|statement of financial|etats? financiers?|annual report)/
    ).map { Regexp.last_match.begin(0) }
    name_positions.product(report_positions).any? { |name_position, report_position| (name_position - report_position).abs <= 200 }
  end

  def fetch_candidate_binary(candidate_row)
    return fetch_common_crawl_capture(candidate_row) if candidate_row["common_crawl_filename"]

    if candidate_row["local_path"]
      path = Pathname(candidate_row.fetch("local_path")).expand_path
      raise "local candidate does not exist: #{path}" unless path.file?

      bytes = path.binread
      return [ bytes, candidate_row.fetch("url"), "application/pdf" ]
    end

    attempts = 0
    deadline = new_request_deadline
    begin
      attempts += 1
      fetch_binary(candidate_row.fetch("url"), max_bytes: 150 * 1024 * 1024, deadline: deadline)
    rescue OpenSSL::SSL::SSLError => error
      raise unless error.message.match?(/certificate verify failed/i)

      fetch_candidate_with_system_curl(candidate_row.fetch("url"), deadline: deadline)
    rescue StandardError => error
      raise unless transient_candidate_error?(error) && attempts < 3

      sleep_with_deadline(2**(attempts - 1), deadline, candidate_row.fetch("url"))
      retry
    end
  rescue StandardError
    raise unless candidate_row["common_crawl_filename"]

    fetch_common_crawl_capture(candidate_row)
  end

  def fetch_candidate_with_system_curl(url, deadline: new_request_deadline)
    timeout_seconds = remaining_request_time(deadline, url)
    max_bytes = 150 * 1024 * 1024
    bytes, stderr, status = capture3_with_timeout(
      "curl", "--fail", "--location", "--max-time", timeout_seconds.ceil.to_s,
      "--max-filesize", max_bytes.to_s, "--silent", "--show-error", "--user-agent", USER_AGENT, url,
      timeout_seconds: timeout_seconds
    )
    raise "system curl failed: #{stderr.strip}" unless status.success?
    raise "system curl response exceeded 150 MiB" if bytes.bytesize > max_bytes

    content_type = bytes.start_with?("%PDF-") ? "application/pdf" : "application/octet-stream"
    [ bytes, url, content_type ]
  end

  def transient_candidate_error?(error)
    error.message.match?(/HTTP (?:429|5\d\d)|connection (?:refused|reset)|timed?\s*out|deadline exceeded|execution expired/i)
  end

  def fetch_common_crawl_capture(candidate_row)
    offset = Integer(candidate_row.fetch("common_crawl_offset"))
    length = Integer(candidate_row.fetch("common_crawl_length"))
    max_record_bytes = 150 * 1024 * 1024
    raise "Common Crawl capture exceeded maximum length" if length > max_record_bytes

    uri = URI("#{COMMON_CRAWL_DATA_ROOT}/#{candidate_row.fetch('common_crawl_filename')}")
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Range"] = "bytes=#{offset}-#{offset + length - 1}"
    response, compressed_record = perform_http_request(
      uri,
      request,
      max_bytes: length + 1_024,
      deadline: new_request_deadline
    )
    raise "Common Crawl range request returned HTTP #{response.code}" unless response.code.to_i == 206

    record = Zlib::GzipReader.new(StringIO.new(compressed_record)).read(max_record_bytes + 1)
    raise "Common Crawl decompressed capture exceeded maximum length" if record.bytesize > max_record_bytes
    _warc_headers, payload = record.split(/\r?\n\r?\n/, 2)
    raise "Common Crawl capture has no HTTP response" unless payload

    http_headers, body = payload.split(/\r?\n\r?\n/, 2)
    raise "Common Crawl capture has no response body" unless body

    content_type = http_headers[/^Content-Type:\s*([^\r\n]+)/i, 1].to_s
    [ body, candidate_row.fetch("url"), content_type ]
  rescue Zlib::GzipFile::Error => error
    raise "invalid Common Crawl capture: #{error.message}"
  end

  def document_types(evidence, candidate_row)
    types = []
    candidate_evidence = "#{candidate_row.fetch('label')} #{candidate_row.fetch('url')}"
    text = evidence.downcase
    types << "statement-of-financial-information" if candidate_evidence.match?(/\bsofi\b|statement[\s_-]*of[\s_-]*financial[\s_-]*information/i)
    annual_report = candidate_evidence.match?(/annual[\s_-]*(?:municipal[\s_-]*)?report|rapport[\s_-]*annuel/i)
    annual_scope = "#{candidate_evidence} #{safe_byteslice(text, 6_000)}"
    types << "annual-report" if annual_report && !annual_scope.match?(NON_CORPORATE_ANNUAL_PATTERN) && !annual_scope.match?(PROGRAM_REPORT_PATTERN)
    independent_auditor_report = text.match?(/independ[ea]nt\s+auditor(?:s\W{0,3}|\W{0,3}s)?\s+report/i)
    legacy_audit_work = [
      [ /we\s+have\s+audited\s+the/i, /in\s+our\s+opinion/i ],
      [
        /(?:\bi\b|\|)\s+have\s+audited\s+the/i,
        /(?:in\s+my\s+opinion|my\s+responsibility\s+is\s+to\s+express\s+an\s+opinion|unable\s+to\s+express\s+an\s+opinion)/i
      ]
    ].any? do |audit_pattern, opinion_pattern|
      text.match?(audit_pattern) && text.match?(opinion_pattern)
    end
    legacy_auditor_report = text.match?(/\bauditor(?:s\W{0,3}|\W{0,3}s)?\s+report/i) &&
      legacy_audit_work &&
      text.match?(/(?:consolidated\s+)?financial\s+statements/i)
    strong_financial = (independent_auditor_report || legacy_auditor_report) &&
      text.match?(/(?:consolidated\s+)?financial\s+statements?|statement\s+of\s+financial\s+(?:position|operations)/i)
    strong_french_financial = text.match?(/rapport\s+de\s+l['’]auditeur\s+ind[ée]pendant/i) &&
      text.match?(/[ée]tats?\s+financiers?|[ée]tat\s+de\s+la\s+situation\s+financi[èe]re|[ée]tat\s+des\s+r[ée]sultats/i)
    financial_report = strong_financial || strong_french_financial
    cover_page = text.split("\f", 2).first.to_s
    financial_scope = "#{candidate_evidence} #{cover_page}"
    types << "financial-statements" if financial_report &&
      !financial_scope.match?(SUBSIDIARY_FINANCIAL_PATTERN) &&
      !financial_scope.match?(NON_MUNICIPAL_FINANCIAL_PATTERN) &&
      !financial_scope.match?(FINANCIAL_HIGHLIGHTS_PATTERN)
    types.uniq
  end

  def institution_matches?(text, official_name)
    normalized_text = normalize(safe_byteslice(text, 100_000))
    cover_text = safe_byteslice(normalized_text, 12_000)
    aliases = [ official_name.to_s, official_name.to_s.gsub(/\s*\([^)]*\)\s*/, " ") ]
      .map { |name| normalize(name) }
      .flat_map do |name|
        without_leading_zero = name.gsub(/\bno\s+0+(\d+)\b/, 'no \1')
        [ name, without_leading_zero, without_leading_zero.gsub(/\bno\s+(\d+)\b/, '\1') ]
      end
      .reject(&:empty?).uniq

    aliases.any? do |normalized_name|
      if (normalized_name.include?(" ") || normalized_name.length >= 5) &&
          cover_text.match?(/\b#{Regexp.escape(normalized_name)}\b/)
        next true
      end

      core_name = normalized_name.split.reject { |token| STOP_TOKENS.include?(token) }.join(" ")
      next false if core_name.empty?
      if (core_name.include?(" ") || core_name.length >= 5) &&
          cover_text.match?(/\b#{Regexp.escape(core_name)}\b/)
        next true
      end

      institutional_forms = [
        "town of #{core_name}", "township of #{core_name}", "city of #{core_name}",
        "village of #{core_name}", "municipality of #{core_name}", "county of #{core_name}",
        "counties of #{core_name}", "district of #{core_name}", "region of #{core_name}",
        "regional municipality of #{core_name}", "corporation of #{core_name}",
        "#{core_name} town council", "#{core_name} municipal council",
        "#{core_name} community government", "#{core_name} inuit community government",
        "ville de #{core_name}", "ville du #{core_name}", "municipalite de #{core_name}",
        "municipalite du #{core_name}", "canton de #{core_name}", "village de #{core_name}",
        "paroisse de #{core_name}", "mrc de #{core_name}", "municipalite regionale de comte de #{core_name}",
        # Apostrophes are deliberately removed by normalize, so French elision
        # such as `Village d'Abercorn` becomes `village dabercorn`. Accept the
        # legal-form contraction, but do not accept the bare name as a substring
        # of a longer word.
        "ville d#{core_name}", "municipalite d#{core_name}", "canton d#{core_name}",
        "village d#{core_name}", "paroisse d#{core_name}",
        "ville d #{core_name}", "municipalite d #{core_name}", "canton d #{core_name}",
        "village d #{core_name}", "paroisse d #{core_name}",
        # Quebec's standardized financial-report cover uses this field pair,
        # including for short names such as Alma and Oka.
        "nom #{core_name} code geographique"
      ]
      institutional_forms.any? { |form| normalized_text.include?(form) }
    end
  end

  def report_year(candidate_row, text)
    content_year = financial_statement_fiscal_year(text)
    return content_year if content_year

    year_sources = [
      candidate_row.fetch("label"),
      url_basename(candidate_row.fetch("url")),
      url_basename(candidate_row.fetch("source_page_url"))
    ]
    year_sources.each do |source|
      valid = source.scan(YEAR_PATTERN).flatten.map(&:to_i).select { |year| valid_year?(year) }
      return valid.first if valid.any?
    end

    contexts = safe_byteslice(text, 40_000).scan(/(?:year|period)\s+ended.{0,100}?(19[89]\d|20\d{2})/im).flatten.map(&:to_i)
    valid = contexts.select { |year| valid_year?(year) }
    return valid.first if valid.any?

    safe_byteslice(text, 10_000).scan(YEAR_PATTERN).flatten.map(&:to_i).select { |year| valid_year?(year) }.max
  end

  # Financial-statement files are often uploaded or republished in the year after
  # the fiscal period. Prefer an explicit period-end statement in the PDF over a
  # year embedded in the link label or URL.
  def financial_statement_fiscal_year(text, max_bytes: 80_000)
    scope = safe_byteslice(text, max_bytes).gsub(/[\u00a0\s]+/, " ")
    patterns = [
      # Prefer the statement title/cover before generic `year ended` prose. An
      # auditor's emphasis paragraph may mention a restated comparative year
      # before repeating the primary fiscal period (for example 2018 inside a
      # 2019 report).
      /(?:consolidated\s+)?financial\s+statements?\b.{0,220}?\b((?:19|20)\d{2})\b/i,
      /(?:for\s+the\s+)?(?:fiscal\s+)?(?:year|period)\s+ended\b.{0,160}?\b((?:19|20)\d{2})\b/i,
      /\bas\s+at\b.{0,100}?\b((?:19|20)\d{2})\b/i,
      /(?:pour\s+)?l['’]\s*exercice(?:\s+financier)?\s+(?:termin[ée]|clos)\b.{0,160}?\b((?:19|20)\d{2})\b/i,
      /[ée]tats?\s+financiers?\b.{0,220}?\b((?:19|20)\d{2})\b/i,
      /\bau\s+(?:\d{1,2}(?:er)?\s+)?(?:janvier|f[ée]vrier|mars|avril|mai|juin|juillet|ao[uû]t|septembre|octobre|novembre|d[ée]cembre)\s+((?:19|20)\d{2})\b/i
    ]
    patterns.each_with_index.filter_map do |pattern, pattern_index|
      match = pattern.match(scope)
      year = match&.captures&.first&.to_i
      next unless year && valid_year?(year)

      [ match.begin(0), pattern_index, year ]
    end.min_by { |position, pattern_index, _year| [ position, pattern_index ] }&.last
  end

  def url_basename(url)
    CGI.unescape(File.basename(URI(url).path))
  rescue URI::InvalidURIError
    ""
  end

  def valid_year?(year)
    year.between?(1980, @retrieved_at.year)
  end

  def safe_byteslice(text, max_bytes)
    text.to_s.byteslice(0, max_bytes).to_s.force_encoding(Encoding::UTF_8).scrub
  end

  def source_languages(text)
    languages = []
    languages << "en" if text.match?(/financial\s+statements?|annual\s+report|independent\s+auditor/i)
    languages << "fr" if text.match?(/[ée]tats?\s+financiers?|rapport\s+(?:annuel|financier)|rapport\s+de\s+l['’]auditeur/i)
    languages.empty? ? [ "en" ] : languages
  end

  def report_title(row, candidate_row, type, year, languages)
    label = candidate_row.fetch("label").gsub(/\s+/, " ").strip
    return label if label.length.between?(8, 240) && label.match?(REPORT_PATTERN)

    descriptors = if languages == [ "fr" ]
      {
        "annual-report" => "Rapport annuel",
        "financial-statements" => "États financiers audités",
        "statement-of-financial-information" => "État de l'information financière"
      }
    else
      {
        "annual-report" => "Annual Report",
        "financial-statements" => "Audited Financial Statements",
        "statement-of-financial-information" => "Statement of Financial Information"
      }
    end
    "#{official_name(row)} #{descriptors.fetch(type)} — #{year}"
  end

  def official_name(row)
    row["official_name_en"] || row["official_name"] || row.fetch("official_name_fr")
  end

  def capture3_with_timeout(*arguments, stdin_data: nil, timeout_seconds: SUBPROCESS_TIMEOUT)
    stdout_data = stderr_data = status = nil
    command_name = arguments.first.is_a?(Hash) ? arguments[1] : arguments.first
    Open3.popen3(*arguments, pgroup: true) do |stdin, stdout, stderr, wait_thread|
      stdin.binmode
      stdout.binmode
      stderr.binmode
      writer = Thread.new do
        stdin.write(stdin_data) if stdin_data
      rescue Errno::EPIPE, IOError
        nil
      ensure
        stdin.close unless stdin.closed?
      end
      stdout_reader = Thread.new { stdout.read }
      stderr_reader = Thread.new { stderr.read }

      begin
        Timeout.timeout(
          timeout_seconds,
          SubprocessDeadlineExceeded,
          "subprocess deadline exceeded for #{command_name}"
        ) do
          status = wait_thread.value
          writer.value
          stdout_data = stdout_reader.value
          stderr_data = stderr_reader.value
        end
      rescue SubprocessDeadlineExceeded
        terminate_subprocess_group(wait_thread)
        raise
      ensure
        [ writer, stdout_reader, stderr_reader ].each do |thread|
          thread.join(1)
          thread.kill if thread.alive?
        end
      end
    end
    [ stdout_data, stderr_data, status ]
  end

  def terminate_subprocess_group(wait_thread)
    Process.kill("TERM", -wait_thread.pid)
    return if wait_thread.join(1)

    Process.kill("KILL", -wait_thread.pid)
    wait_thread.join
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def pdf_text(bytes, max_pages: 40, fallback_to_ocr: true)
    arguments = [ "pdftotext" ]
    arguments.concat([ "-f", "1", "-l", max_pages.to_s ]) if max_pages
    arguments.concat([ "-layout", "-", "-" ])
    stdout, stderr, status = capture3_with_timeout(*arguments, stdin_data: bytes)
    raise "pdftotext failed: #{stderr.strip}" unless status.success?
    text = stdout.force_encoding("UTF-8").scrub
    return text if text.strip.length >= 50 || !fallback_to_ocr

    ocr_pdf_text(bytes)
  end

  def pdf_page_count(bytes)
    stdout, stderr, status = capture3_with_timeout("pdfinfo", "-", stdin_data: bytes)
    raise "pdfinfo failed: #{stderr.strip}" unless status.success?

    pages = stdout[/^Pages:\s+(\d+)$/i, 1]&.to_i
    raise "pdfinfo did not report a page count" unless pages&.positive?

    pages
  end

  def ocr_pdf_text(bytes, max_pages: 5, dpi: 150, first_page: 1, last_page: nil, allow_empty: false)
    last_page ||= max_pages ? first_page + max_pages - 1 : nil
    raise "invalid OCR page range" unless first_page.positive? && (!last_page || last_page >= first_page)

    Dir.mktmpdir("york-municipal-report-") do |directory|
      input = File.join(directory, "input.pdf")
      prefix = File.join(directory, "page")
      File.binwrite(input, bytes)
      arguments = [ "pdftoppm", "-f", first_page.to_s ]
      arguments.concat([ "-l", last_page.to_s ]) if last_page
      arguments.concat([ "-jpeg", "-r", dpi.to_s, input, prefix ])
      _stdout, stderr, status = capture3_with_timeout(*arguments)
      raise "pdftoppm failed: #{stderr.strip}" unless status.success?

      images = Dir.glob("#{prefix}-*.jpg").sort
      text = ocr_images_text(images)
      raise "PDF has no extractable or OCR-readable text" if !allow_empty && text.strip.length < 50

      text
    end
  end

  def ocr_images_text(images)
    return "" if images.empty?

    first_text = tesseract_image_text(images.first)
    rotation, first_text = preferred_ocr_rotation(images.first, first_text)
    remaining = images.drop(1).map { |image| ocr_text_at_rotation(image, rotation) }
    [ first_text, *remaining ].join("\f")
  end

  def preferred_ocr_rotation(image, normal_text)
    normal = [ 0, normal_text ]
    return normal if ocr_orientation_score(normal_text) >= OCR_ORIENTATION_SCORE_THRESHOLD

    alternatives = [ 90, 270 ].filter_map do |rotation|
      [ rotation, ocr_text_at_rotation(image, rotation) ]
    rescue StandardError
      nil
    end
    ([ normal ] + alternatives).max_by do |_rotation, text|
      [ ocr_orientation_score(text), text.scan(/[[:alpha:]]/).length ]
    end
  end

  def ocr_orientation_score(text)
    normalized = normalize(text)
    term_score = normalized.scan(OCR_ORIENTATION_TERMS).length * 5
    year_score = normalized.scan(/\b(?:19|20)\d{2}\b/).length * 3
    readable_words = normalized.scan(/\b[a-z]{3,}\b/).length.clamp(0, 10)
    term_score + year_score + readable_words
  end

  def ocr_text_at_rotation(image, rotation)
    return tesseract_image_text(image) if rotation.zero?

    command = image_rotation_command
    raise "ImageMagick is unavailable for rotated OCR" unless command

    rotated = "#{image}.rotated-#{rotation}.jpg"
    _stdout, stderr, status = capture3_with_timeout(command, image, "-rotate", rotation.to_s, rotated)
    raise "image rotation failed: #{stderr.strip}" unless status.success?

    tesseract_image_text(rotated)
  ensure
    FileUtils.rm_f(rotated) if defined?(rotated) && rotated
  end

  def tesseract_image_text(image)
    page_text, page_error, page_status = capture3_with_timeout(
      TESSERACT_ENV,
      "tesseract", image, "stdout", "--tessdata-dir", TESSDATA_DIR.to_s, "-l", "eng+fra"
    )
    raise "tesseract failed: #{page_error.strip}" unless page_status.success?

    page_text.force_encoding(Encoding::UTF_8).scrub
  end

  def image_rotation_command
    @image_rotation_command ||= ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).filter_map do |directory|
      candidate = File.join(directory, "magick")
      candidate if File.file?(candidate) && File.executable?(candidate)
    end.first
  end

  def archive_pdf(bytes)
    hash = Digest::SHA256.hexdigest(bytes)
    relative = Pathname("sha256").join(hash[0, 2], "#{hash}.pdf")
    destination = @asset_root.join(relative)
    @mutex.synchronize do
      FileUtils.mkdir_p(destination.dirname)
      destination.binwrite(bytes) unless destination.exist?
    end
    {
      "content_sha256" => hash,
      "byte_size" => bytes.bytesize,
      "mime_type" => "application/pdf",
      "archive_path" => relative.to_s
    }
  end

  def gaps(candidate_count, reports, discovery_errors, candidate_errors)
    gaps = []
    gaps << "No financial statement, SOFI, or annual report PDF was verified from the official website." if reports.empty?
    gaps << "Discovery found #{candidate_count} candidates; validation was capped at #{@max_documents}." if candidate_count > @max_documents
    gaps << "#{discovery_errors.length} discovery requests failed." if discovery_errors.any?
    gaps << "#{candidate_errors.length} candidate PDFs failed download or content validation." if candidate_errors.any?
    gaps
  end

  def search_paths(root)
    [ "financial statements", "audited financial statements", "annual report", "états financiers", "rapport financier", "rapport annuel" ].flat_map do |query|
      encoded = URI.encode_www_form_component(query)
      [
        URI.join(root, "/?s=#{encoded}").to_s,
        URI.join(root, "/search?query=#{encoded}").to_s,
        URI.join(root, "/search/node?keys=#{encoded}").to_s,
        URI.join(root, "/recherche?q=#{encoded}").to_s,
        URI.join(root, "/recherche?query=#{encoded}").to_s,
        URI.join(root, "/wp-json/wp/v2/search?search=#{encoded}&per_page=100").to_s
      ]
    end
  end

  def site_root(url)
    uri = URI(url)
    uri.path = "/"
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  end

  def website_host(url)
    URI(url.to_s).host.to_s.downcase.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    ""
  end

  def likely_pdf_url?(url)
    uri = URI(url)
    return false unless %w[http https].include?(uri.scheme&.downcase)

    evidence = CGI.unescape([ uri.path, uri.query ].compact.join("?"))
    evidence.match?(PDF_PATTERN) || evidence.match?(OPAQUE_DOCUMENT_URL_PATTERN)
  rescue URI::InvalidURIError
    false
  end

  def normalized_url(url)
    uri = URI(url)
    uri.fragment = nil
    uri.host = uri.host&.downcase
    uri.to_s
  rescue URI::Error
    url
  end

  def normalize(value)
    utf8 = value.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    utf8.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.delete("'").gsub(/[^a-z0-9]+/, " ").strip
  end

  def fetch_text(url, max_bytes: 20 * 1024 * 1024, user_agent: USER_AGENT, deadline: nil)
    body, resolved_url, = fetch_binary(
      url,
      max_bytes: max_bytes,
      user_agent: user_agent,
      deadline: deadline
    )
    [ body.force_encoding("UTF-8").scrub, resolved_url ]
  end

  def fetch_binary(url, max_bytes:, redirects: 8, user_agent: USER_AGENT, deadline: nil)
    raise "too many redirects for #{url}" if redirects.zero?

    deadline ||= new_request_deadline
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = user_agent
    request["Accept"] = "text/html,application/xhtml+xml,application/pdf,application/xml;q=0.9,*/*;q=0.5"
    cookie_header = cookies_for(uri.host)
    request["Cookie"] = cookie_header unless cookie_header.empty?
    response, body = perform_http_request(uri, request, max_bytes: max_bytes, deadline: deadline)
    store_response_cookies(uri.host, response)
    if response.is_a?(Net::HTTPRedirection)
      location = response["location"]
      raise "redirect without location from #{url}" if location.to_s.empty?

      return fetch_binary(
        URI.join(uri, location).to_s,
        max_bytes: max_bytes,
        redirects: redirects - 1,
        user_agent: user_agent,
        deadline: deadline
      )
    end
    raise "HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

    [ body, uri.to_s, response["content-type"].to_s ]
  end

  def perform_http_request(uri, request, max_bytes:, deadline:)
    response = nil
    body = String.new(capacity: [ max_bytes, 1_048_576 ].min, encoding: Encoding::BINARY)
    timeout_seconds = remaining_request_time(deadline, uri.to_s)
    Timeout.timeout(
      timeout_seconds,
      RequestDeadlineExceeded,
      "request deadline exceeded for #{uri}"
    ) do
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: [ HTTP_OPEN_TIMEOUT, timeout_seconds ].min,
        read_timeout: [ HTTP_READ_TIMEOUT, timeout_seconds ].min
      ) do |http|
        http.request(request) do |streaming_response|
          response = streaming_response
          content_length = streaming_response["content-length"].to_i
          if content_length.positive? && content_length > max_bytes
            raise "response exceeded #{max_bytes} bytes"
          end

          bytes_read = 0
          retain_body = streaming_response.code.to_i.between?(200, 299)
          streaming_response.read_body do |chunk|
            remaining_request_time(deadline, uri.to_s)
            bytes_read += chunk.bytesize
            raise "response exceeded #{max_bytes} bytes" if bytes_read > max_bytes

            body << chunk if retain_body
          end
        end
      end
    end
    [ response, body ]
  end

  def new_request_deadline(timeout_seconds = HTTP_REQUEST_TIMEOUT)
    monotonic_now + timeout_seconds
  end

  def remaining_request_time(deadline, description)
    remaining = deadline - monotonic_now
    return remaining if remaining.positive?

    raise RequestDeadlineExceeded, "request deadline exceeded for #{description}"
  end

  def sleep_with_deadline(seconds, deadline, description)
    sleep([ seconds, remaining_request_time(deadline, description) ].min)
    remaining_request_time(deadline, description)
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def cookies_for(host)
    @cookie_mutex.synchronize do
      @cookies_by_host.fetch(host, {}).map { |name, value| "#{name}=#{value}" }.join("; ")
    end
  end

  def store_response_cookies(host, response)
    values = response.get_fields("set-cookie").to_a
    return if values.empty?

    @cookie_mutex.synchronize do
      values.each do |header|
        name, value = header.split(";", 2).first.to_s.split("=", 2)
        next if name.to_s.empty? || value.nil?

        @cookies_by_host[host][name] = value
      end
    end
  end

  def parallel_map(rows)
    queue = Queue.new
    rows.each_with_index { |row, index| queue << [ index, row ] }
    results = Array.new(rows.length)
    Array.new(@threads) do
      Thread.new do
        loop do
          index, row = queue.pop(true)
          results[index] = yield(row)
        rescue ThreadError
          break
        end
      end
    end.each(&:join)
    results
  end

  def write_institution_audit(row, result)
    path = institution_audit_path(row)
    @mutex.synchronize { path.write(JSON.pretty_generate(result) << "\n") }
  end

  def institution_audit_path(row)
    @raw_dir.join("institutions", "#{row.fetch('canonical_id').tr('/', '__')}.json")
  end

  def write_batch(payload, rows, results)
    reports = results.flat_map { |result| result.fetch("reports") }
    batch = {
      "batch" => "#{payload.fetch('province').fetch('code')}-municipal-financial-reports",
      "source_manifest" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "retrieved_at" => @retrieved_at.iso8601,
      "institution_count" => rows.length,
      "institutions_with_reports" => results.count { |result| result.fetch("reports").any? },
      "validated_report_count" => reports.length,
      "financial_statement_count" => reports.count { |report| report.fetch("document_type") == "financial-statements" },
      "annual_report_count" => reports.count { |report| report.fetch("document_type") == "annual-report" },
      "sofi_count" => reports.count { |report| report.fetch("document_type") == "statement-of-financial-information" },
      "institutions" => results
    }
    path = @output_dir.join("financial-report-batch.json")
    path.write(JSON.pretty_generate(batch) << "\n")
    puts JSON.pretty_generate(batch.slice("institution_count", "institutions_with_reports", "validated_report_count", "financial_statement_count", "annual_report_count", "sofi_count"))
    puts "output=#{path}"
    puts "sha256=#{Digest::SHA256.file(path).hexdigest}"
  end
end

if $PROGRAM_NAME == __FILE__
  options = { threads: 6, max_pages: 40, max_documents: 100 }
  OptionParser.new do |parser|
  parser.banner = "Usage: scrape_municipal_financial_reports.rb --manifest PATH --output-dir PATH --retrieved-at ISO8601"
  parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
  parser.on("--output-dir PATH") { |value| options[:output_dir] = value }
  parser.on("--retrieved-at TIME") { |value| options[:retrieved_at] = value }
  parser.on("--threads N", Integer) { |value| options[:threads] = value }
  parser.on("--max-pages N", Integer) { |value| options[:max_pages] = value }
  parser.on("--max-documents N", Integer) { |value| options[:max_documents] = value }
  parser.on("--asset-root PATH") { |value| options[:asset_root] = Pathname(value) }
  parser.on("--canonical-ids IDS", "Comma-separated canonical IDs") do |value|
    options[:canonical_ids] ||= []
    options[:canonical_ids].concat(value.split(",").map(&:strip).reject(&:empty?))
  end
  parser.on("--canonical-ids-file PATH", "One canonical ID per line") do |value|
    options[:canonical_ids] ||= []
    options[:canonical_ids].concat(
      Pathname(value).read.lines.map(&:strip).reject { _1.empty? || _1.start_with?("#") }
    )
  end
  parser.on("--exclude-municipality-types TYPES", "Comma-separated municipality types") do |value|
    options[:exclude_municipality_types] = value.split(",").map(&:strip).reject(&:empty?)
  end
  parser.on("--exclude-canonical-ids IDS", "Comma-separated canonical IDs") do |value|
    options[:exclude_canonical_ids] ||= []
    options[:exclude_canonical_ids].concat(value.split(",").map(&:strip).reject(&:empty?))
  end
  parser.on("--exclude-canonical-ids-file PATH", "One excluded canonical ID per line") do |value|
    options[:exclude_canonical_ids] ||= []
    options[:exclude_canonical_ids].concat(
      Pathname(value).read.lines.map(&:strip).reject { _1.empty? || _1.start_with?("#") }
    )
  end
  parser.on("--exclude-website-hosts HOSTS", "Comma-separated website hosts") do |value|
    options[:exclude_website_hosts] = value.split(",").map(&:strip).reject(&:empty?)
  end
  parser.on("--include-wayback", "Discover historical PDFs in the Internet Archive CDX index") do
    options[:include_wayback] = true
  end
  parser.on("--wayback-only", "Skip live-site discovery and use only the Internet Archive CDX index") do
    options[:include_wayback] = true
    options[:wayback_only] = true
  end
  parser.on("--include-common-crawl", "Discover PDFs in recent Common Crawl indexes") do
    options[:include_common_crawl] = true
  end
  parser.on("--common-crawl-only", "Skip live-site discovery and use only recent Common Crawl indexes") do
    options[:include_common_crawl] = true
    options[:common_crawl_only] = true
  end
  parser.on("--common-crawl-collections N", Integer, "Number of recent Common Crawl indexes to search") do |value|
    options[:common_crawl_collections] = value
  end
  parser.on("--missing-financial-statements-only", "Search only institutions without an archived statement") do
    options[:missing_financial_statements_only] = true
  end
  parser.on("--deep-crawl", "Traverse bounded internal document and governance pages") do
    options[:deep_crawl] = true
  end
  parser.on("--include-opaque-archive-pdfs", "Content-validate archive PDFs whose URLs have no report keywords") do
    options[:include_opaque_archive_pdfs] = true
  end
  parser.on("--include-web-search", "Discover official-domain PDFs through bounded web search queries") do
    options[:include_web_search] = true
  end
  parser.on("--web-search-only", "Skip site crawling and use only bounded official-domain web search results") do
    options[:include_web_search] = true
    options[:web_search_only] = true
  end
  parser.on("--web-search-provider PROVIDER", MunicipalFinancialReportScraper::WEB_SEARCH_PROVIDERS,
    "Web search provider (brave, duckduckgo, or yahoo; default: brave)") do |value|
    options[:web_search_provider] = value
  end
  parser.on("--web-search-query-set SET", %w[full audit],
    "Web search query set (full or audit; default: full)") do |value|
    options[:web_search_query_set] = value
  end
  parser.on("--include-trusted-portal-search",
    "Also search recognized municipal document portals using the institution name") do
    options[:include_trusted_portal_search] = true
  end
  parser.on("--trusted-portal-search-only",
    "Skip official-domain queries and search only recognized municipal document portals") do
    options[:include_web_search] = true
    options[:web_search_only] = true
    options[:include_trusted_portal_search] = true
    options[:trusted_portal_search_only] = true
  end
  parser.on("--institution-name-search-only",
    "Search by the institution's legal-form name and content-validate PDFs from any result host") do
    options[:include_web_search] = true
    options[:web_search_only] = true
    options[:institution_name_search_only] = true
  end
  parser.on("--revalidate-candidates-from DIR", "Recheck PDF candidates from prior institution audit JSON files") do |value|
    options[:revalidate_candidates_from] = Pathname(value)
  end
  parser.on("--existing-audits-only", "Finalize a partial batch using only already-written institution audits") do
    options[:existing_audits_only] = true
  end
  end.parse!

  missing = %i[manifest_path output_dir retrieved_at].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  MunicipalFinancialReportScraper.new(**options).run
end
