#!/usr/bin/env ruby

require "cgi"
require "csv"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "open3"
require "optparse"
require "pathname"
require "set"
require "time"
require "uri"

class WesternMunicipalFinancialReportScraper
  class ScrapeError < StandardError; end

  USER_AGENT = "Build Canada public-institution ontology archival scraper/1.0"
  ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  STATCAN_STRUCTURE = Pathname(
    "/Volumes/floppy/york_factory/public_institutions/sources/ns-municipalities/" \
      "2026-08-19/sgc-cgt-2021-structure-eng.csv"
  )
  STATCAN_URL = "https://www.statcan.gc.ca/en/subjects/standard/sgc/2021/index"

  ALBERTA_TYPES = {
    "CITY" => "City",
    "SMUN" => "Specialized Municipality",
    "RMUN" => "Municipal District",
    "TOWN" => "Town",
    "VILG" => "Village",
    "SVIL" => "Summer Village",
    "IDST" => "Improvement District",
    "SARE" => "Special Area"
  }.freeze

  REPORT_PATTERN = /(?:audited?[\s_-]*financial|financial[\s_-]*statements?|consolidated[\s_-]*financial|annual[\s_-]*(?:municipal[\s_-]*)?reports?|statement[\s_-]*of[\s_-]*financial[\s_-]*information|\bsofi\b)/i
  EXCLUDE_PATTERN = /(?:budget|financial[\s_-]*plan|quarterly|interim|grant|policy|template|guide|agenda|minutes)/i
  NON_MUNICIPAL_REPORT_PATTERN = /(?:drinking[\s_-]*water|water[\s_-]*(?:quality|monitoring|treatment)|wastewater|solid[\s_-]*waste|fire(?:[\s_-]*(?:department|rescue))?|library|museum|tourism|police|transit)[\s_-]*(?:.*[\s_-])?annual[\s_-]*report|annual[\s_-]*(?:.*[\s_-])?(?:drinking[\s_-]*water|water[\s_-]*(?:quality|monitoring|treatment)|wastewater|solid[\s_-]*waste|fire(?:[\s_-]*(?:department|rescue))?|library|museum|tourism|police|transit)/i
  BC_VERIFIED_REPORTS = {
    "ca/fn/shishalh-nation-government-district" => [
      {
        url: "https://shishalh.com/wp-content/uploads/2023/09/Sechelt-Indian-Government-District-2021-Finalized-Financial-Statements.pdf",
        label: "Sechelt Indian Government District 2021 Finalized Financial Statements",
        source_page_url: "https://shishalh.com/wp-content/uploads/2023/09/Sechelt-Indian-Government-District-2021-Finalized-Financial-Statements.pdf"
      }
    ]
  }.freeze

  def initialize(province:, output_dir:, retrieved_at:, threads: 8, asset_root: ASSET_ROOT,
    statcan_structure: STATCAN_STRUCTURE, max_bc_pages: 40, contacts_only: false, retry_gaps: false,
    repair_collisions: false, repair_geographies: false, normalize_bc_reports: false,
    retry_bc_missing: false, add_bc_known_reports: false)
    @province = province
    @output_dir = Pathname(output_dir)
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @threads = Integer(threads)
    @asset_root = Pathname(asset_root).expand_path
    @statcan_structure = Pathname(statcan_structure)
    @max_bc_pages = Integer(max_bc_pages)
    @contacts_only = contacts_only
    @retry_gaps = retry_gaps
    @repair_collisions = repair_collisions
    @repair_geographies = repair_geographies
    @normalize_bc_reports = normalize_bc_reports
    @retry_bc_missing = retry_bc_missing
    @add_bc_known_reports = add_bc_known_reports
    @raw_dir = @output_dir.join("raw")
    @mutex = Mutex.new
  end

  def call
    raise ScrapeError, "province must be ab or bc" unless %w[ab bc].include?(@province)

    FileUtils.mkdir_p(@raw_dir)
    FileUtils.mkdir_p(@asset_root.join("sha256"))
    return repair_alberta_contacts if @contacts_only && @province == "ab"
    return retry_alberta_report_gaps if @retry_gaps && @province == "ab"
    return repair_alberta_canonical_collisions if @repair_collisions && @province == "ab"
    return repair_bc_canonical_collisions if @repair_collisions && @province == "bc"
    return repair_geographies if @repair_geographies
    return normalize_bc_reports if @normalize_bc_reports && @province == "bc"
    return retry_bc_missing_reports if @retry_bc_missing && @province == "bc"
    return add_bc_known_reports if @add_bc_known_reports && @province == "bc"
    raise ScrapeError, "--contacts-only is currently supported only for Alberta" if @contacts_only
    raise ScrapeError, "--retry-gaps is currently supported only for Alberta" if @retry_gaps
    raise ScrapeError, "--normalize-bc-reports is supported only for British Columbia" if @normalize_bc_reports
    raise ScrapeError, "--retry-bc-missing is supported only for British Columbia" if @retry_bc_missing
    raise ScrapeError, "--add-bc-known-reports is supported only for British Columbia" if @add_bc_known_reports

    payload = @province == "ab" ? scrape_alberta : scrape_british_columbia
    write_json(@output_dir.join("normalized-municipalities.json"), payload.fetch(:base))
    write_json(@output_dir.join("financial-report-batch.json"), payload.fetch(:batch))
    write_json(@output_dir.join("scrape-summary.json"), payload.fetch(:summary))
    payload.fetch(:summary)
  end

  private

  def scrape_alberta
    roster_url = "https://municipalaffairs.gov.ab.ca/mc_financial_tax_bylaws.cfm"
    profile_url = "https://municipalaffairs.gov.ab.ca/cfml/MunicipalProfiles/index"
    search_html = fetch(roster_url.sub("https://", "http://"))
    @raw_dir.join("audited-financial-statements-search.html").binwrite(search_html)
    document = Nokogiri::HTML(search_html)
    municipalities = []

    ALBERTA_TYPES.each do |type_code, legal_form|
      names = document.css("#selectLegalName#{type_code} option").drop(1).map { |option| option.text.strip }
      profile_rows = fetch_alberta_profile_rows(type_code, legal_form)
      profile_by_name = profile_rows.to_h { |row| [ row.fetch("NAME"), row ] }
      names.each do |official_name|
        profile = profile_by_name.fetch(official_name) do
          raise ScrapeError, "profile directory omitted #{official_name} (#{type_code})"
        end
        municipalities << alberta_municipality_row(official_name, type_code, legal_form, profile.fetch("SKHDID"))
      end
    end
    resolve_canonical_collisions!(municipalities)

    parallel_each(municipalities) do |row|
      enrich_alberta_contact!(row, profile_url)
    rescue StandardError => error
      row["contact_errors"] << "contact profile: #{error.message}"
      row["website_url"] ||= fallback_alberta_website(row)
    end

    statement_rows = parallel_map(municipalities) do |row|
      scrape_alberta_statements(row, roster_url)
    rescue StandardError => error
      {
        "canonical_id" => row.fetch("canonical_id"),
        "searched_locations" => [ roster_url ],
        "gaps" => [ "statement archive scrape failed: #{error.message}" ],
        "financial_statements" => []
      }
    end

    attach_statcan!(municipalities, province_code: "48")
    municipalities.each { |row| row["website_url"] ||= fallback_alberta_website(row) }
    build_payload(
      municipalities: municipalities,
      report_rows: statement_rows,
      province: {
        "code" => "ab",
        "statcan_code" => "48",
        "name_en" => "Alberta",
        "name_fr" => "Alberta",
        "government_name_en" => "Government of Alberta",
        "government_name_fr" => nil,
        "website_url" => "https://www.alberta.ca/",
        "source_languages" => [ "en" ],
        "source_license" => "Open Government Licence - Alberta"
      },
      roster_url: roster_url,
      roster_title: "Municipal Affairs audited financial statements and municipal profiles"
    )
  end

  def fetch_alberta_profile_rows(type_code, legal_form)
    endpoint = "https://municipalaffairs.gov.ab.ca/cfml/MunicipalProfiles/proxy.cfm/getMunicipality"
    query = URI.encode_www_form(munDesc: legal_form, munType: type_code)
    body = fetch("#{endpoint}?#{query}")
    @raw_dir.join("profile-roster-#{type_code.downcase}.json").binwrite(body)
    JSON.parse(body).fetch("CONTENTS")
  end

  def alberta_municipality_row(official_name, type_code, legal_form, code)
    {
      "official_name" => official_name,
      "canonical_id" => "ca/ab/#{institution_slug(official_name, legal_form)}",
      "municipality_type" => legal_form,
      "government_level" => type_code == "SARE" ? "regional" : "municipal",
      "website_url" => nil,
      "website_source_url" => "https://municipalaffairs.gov.ab.ca/cfml/MunicipalProfiles/index",
      "identifiers" => [
        {
          "scheme" => "ab.municipal_code",
          "value" => format("%04d", Integer(code)),
          "preferred" => true,
          "source_url" => "https://municipalaffairs.gov.ab.ca/cfml/MunicipalProfiles/index"
        }
      ],
      "statcan_csd_uids" => [],
      "statcan_geographies" => [],
      "financial_statements" => [],
      "annual_reports" => [],
      "contact" => {},
      "sources" => [],
      "contact_errors" => [],
      "statement_errors" => [],
      "_type_code" => type_code,
      "_municipal_code" => format("%04d", Integer(code))
    }
  end

  def enrich_alberta_contact!(row, profile_url)
    body = post_form(
      profile_url,
      fuseaction: "BasicReport",
      MunicipalityType: row.fetch("_type_code"),
      stakeholder: row.fetch("_municipal_code").to_i,
      profileType: "CONT"
    )
    raise ScrapeError, "contact response is not a PDF" unless body.start_with?("%PDF-")

    raw_path = @raw_dir.join("contact-profiles", "#{row.fetch('_municipal_code')}.pdf")
    FileUtils.mkdir_p(raw_path.dirname)
    raw_path.binwrite(body)
    text, status = Open3.capture2("pdftotext", "-layout", "-", "-", stdin_data: body)
    raise ScrapeError, "pdftotext failed" unless status.success?

    website = text[/Web Site:\s*(\S+)/, 1]
    email = text[/Email:\s*(\S+)/, 1]
    phone = text[/Phone:\s*([0-9().+ -]+)/, 1]&.strip
    row["website_url"] = normalize_website(website) if website
    row["contact"]["email"] = email unless email.to_s.empty?
    row["contact"]["phone"] = phone unless phone.to_s.empty?
    row["sources"] << source_record(
      url: profile_url,
      publisher: "Government of Alberta",
      title: "Municipal Contacts Profile - #{row.fetch('official_name')}",
      license: "Open Government Licence - Alberta"
    )
  end

  def fallback_alberta_website(row)
    return "https://www.alberta.ca/improvement-districts" if row.fetch("_type_code") == "IDST"

    row.fetch("website_source_url")
  end

  def scrape_alberta_statements(row, roster_url)
    query = URI.encode_www_form(
      fuseaction: "FinancialStatementsTaxRatesSearch",
      muniType: row.fetch("_type_code"),
      legalName: row.fetch("official_name"),
      audFinStat: "fs"
    )
    source_page_url = "#{roster_url}?#{query}"
    html = fetch(source_page_url.sub("https://", "http://"))
    document = Nokogiri::HTML(html)
    links = document.css("a[href*='/pdf/fs/']").map do |anchor|
      URI.join(roster_url, anchor["href"].gsub(" ", "%20")).to_s
    end.uniq
    statements = links.filter_map do |download_url|
      year = File.basename(URI(download_url).path)[/\A(20\d{2})_/, 1]
      next unless year

      archive_pdf(download_url).merge(
        "canonical_id" => row.fetch("canonical_id"),
        "title" => "#{row.fetch('official_name')} Audited Financial Statements — December 31, #{year}",
        "document_type" => "financial-statements",
        "document_variant" => "consolidated",
        "fiscal_period_start" => "#{year}-01-01",
        "fiscal_period_end" => "#{year}-12-31",
        "published_on" => nil,
        "source_page_url" => source_page_url,
        "download_url" => download_url,
        "languages" => [ "en" ],
        "retrieved_at" => @retrieved_at.iso8601,
        "rights_status" => "metadata_only",
        "notes" => "Official Alberta Municipal Affairs audited-financial-statement archive."
      )
    rescue StandardError => error
      row["statement_errors"] << "#{download_url}: #{error.message}"
      nil
    end

    {
      "canonical_id" => row.fetch("canonical_id"),
      "searched_locations" => [ source_page_url ],
      "gaps" => row.fetch("statement_errors"),
      "financial_statements" => statements.sort_by { |statement| statement.fetch("fiscal_period_end") }
    }
  end

  def scrape_british_columbia
    roster_url = "https://www.civicinfo.bc.ca/municipalities"
    pages = (1..7).map do |page|
      url = "https://r.jina.ai/http://www.civicinfo.bc.ca/municipalities?pn=#{page}&refresh=#{@retrieved_at.to_date.strftime('%Y%m%d')}"
      body = fetch(url)
      @raw_dir.join("civicinfo-municipalities-page-#{page}.md").binwrite(body)
      body
    end
    municipalities = pages.flat_map { |body| parse_civicinfo_page(body) }
      .uniq { |row| row.fetch("civicinfo_id") }
      .sort_by { |row| row.fetch("official_name") }
    raise ScrapeError, "expected 162 BC municipality records, got #{municipalities.length}" unless municipalities.length == 162

    municipalities.each do |row|
      row["canonical_id"] = bc_canonical_id(row)
      row["government_level"] = "municipal"
      if row["canonical_id"] == "ca/bc/okanagan-falls"
        row["website_url"] = "https://engage.gov.bc.ca/govtogetherbc/engagement/okanaganfalls/"
        row["website_source_url"] = row["website_url"]
        row["status"] = "proposed"
        row["active_from"] = "2026-11-06"
        row["description_en"] = "Letters patent were issued June 24, 2026; incorporation takes effect November 6, 2026."
      end
      row["identifiers"] = [
        {
          "scheme" => "civicinfo.bc.organization",
          "value" => row.delete("civicinfo_id").to_s,
          "preferred" => true,
          "source_url" => roster_url
        }
      ]
      row["statcan_csd_uids"] = []
      row["statcan_geographies"] = []
      row["financial_statements"] = []
      row["annual_reports"] = []
      row["sources"] = [ source_record(
        url: roster_url,
        publisher: "CivicInfo BC",
        title: "British Columbia Municipalities Directory"
      ) ]
      row["scrape_errors"] = []
    end
    resolve_bc_canonical_collisions!(municipalities)
    attach_statcan!(municipalities, province_code: "59")

    report_rows = parallel_map(municipalities) do |row|
      scrape_bc_site(row)
    rescue StandardError => error
      {
        "canonical_id" => row.fetch("canonical_id"),
        "searched_locations" => [ row.fetch("website_url") ],
        "gaps" => [ "municipal-site scrape failed: #{error.message}" ],
        "financial_statements" => []
      }
    end

    build_payload(
      municipalities: municipalities,
      report_rows: report_rows,
      province: {
        "code" => "bc",
        "statcan_code" => "59",
        "name_en" => "British Columbia",
        "name_fr" => "Colombie-Britannique",
        "government_name_en" => "Government of British Columbia",
        "government_name_fr" => nil,
        "website_url" => "https://www2.gov.bc.ca/",
        "source_languages" => [ "en" ],
        "source_license" => nil
      },
      roster_url: roster_url,
      roster_title: "British Columbia Municipalities Directory",
      roster_publisher: "CivicInfo BC"
    )
  end

  def parse_civicinfo_page(markdown)
    markdown = markdown.dup.force_encoding(Encoding::UTF_8).scrub
    entry_pattern = /(?:\A|\n)(\d+)\.\s+.*?\[\*\*(.+?)\*\*\]\([^\n]*?id=(\d+)[^)]*\)\s*\n(.*?)\n\nPh:\s*([^\n]+)\n\n(.*?)(?=\n\d+\.\s+|\n\*\s+\[(?:< Previous|Next >)|\z)/m
    markdown.scan(entry_pattern).map do |_position, display_name, id, address, phone, remainder|
      name, type = display_name.match(/\A(.+) \(([^)]+)\)\z/)&.captures || [ display_name, inferred_bc_type(display_name) ]
      website = remainder.scan(/\[(https?:\/\/[^\]]+)\]\((https?:\/\/[^)]+)\)/).flatten
        .find { |url| !url.include?("civicinfo.bc.ca") && !url.include?("amazonaws.com") }
      email = remainder[/\[([^\]]+@[^\]]+)\]\(mailto:/, 1]
      raise ScrapeError, "CivicInfo entry #{name} has no website" unless website

      {
        "official_name" => bc_official_name(name, type),
        "directory_name" => name,
        "municipality_type" => type,
        "website_url" => website,
        "website_source_url" => "https://www.civicinfo.bc.ca/municipalities?id=#{id}",
        "contact" => {
          "mailing_address" => address.strip,
          "phone" => phone.strip,
          "email" => email
        }.compact,
        "civicinfo_id" => id
      }
    end
  end

  def inferred_bc_type(name)
    return "Indian Government District" if name.match?(/Nation Government District/i)
    return "Community Government" if name.match?(/Community Government/i)

    "Other Municipality"
  end

  def bc_official_name(name, type)
    case type
    when "City" then "City of #{name}"
    when "Town" then "Town of #{name}"
    when "Village" then "Village of #{name}"
    when "District" then "District of #{name}"
    when "Township" then "Township of #{name}"
    when "Island Municipality" then "Bowen Island Municipality"
    when "Resort Municipality" then "Resort Municipality of #{name}"
    when "Mountain Resort Municipality" then "#{name} Mountain Resort Municipality"
    when "Regional Municipality" then "#{name} Regional Municipality"
    else name
    end
  end

  def bc_canonical_id(row)
    "ca/bc/#{slugify(row.fetch('directory_name'))}"
  end

  def scrape_bc_site(row)
    website = normalize_website(row.fetch("website_url"))
    discovered_pages, direct_candidates, searched = discover_site_reports(website)
    candidates = direct_candidates.dup
    discovered_pages.first(@max_bc_pages).each do |page_url|
      begin
        body = fetch_with_jina_fallback(page_url)
        candidates.concat(extract_report_links(body, page_url))
      rescue StandardError => error
        row["scrape_errors"] << "#{page_url}: #{error.message}"
      end
    end
    candidates.uniq! { |candidate| normalized_url(candidate.fetch(:url)) }

    reports = candidates.filter_map do |candidate|
      classify_and_archive_bc_report(row, candidate)
    rescue StandardError => error
      row["scrape_errors"] << "#{candidate.fetch(:url)}: #{error.message}"
      nil
    end

    {
      "canonical_id" => row.fetch("canonical_id"),
      "searched_locations" => searched.uniq.sort,
      "gaps" => row.fetch("scrape_errors").uniq,
      "financial_statements" => reports.reject { |report| report["document_type"] == "annual-report" },
      "annual_reports" => reports.select { |report| report["document_type"] == "annual-report" }
    }
  end

  def discover_site_reports(website)
    origin = URI(website)
    origin.path = "/"
    origin.query = nil
    origin.fragment = nil
    root = origin.to_s
    searched = [ root ]
    sitemap_urls = Set.new
    begin
      robots_url = URI.join(root, "/robots.txt").to_s
      robots = fetch(robots_url)
      searched << robots_url
      robots.scan(/^Sitemap:\s*(\S+)/i) { |match| sitemap_urls << match.first }
    rescue StandardError
      # Conventional sitemap locations are attempted below.
    end
    %w[/sitemap.xml /sitemap_index.xml /wp-sitemap.xml].each do |path|
      sitemap_urls << URI.join(root, path).to_s
    end

    all_urls = Set.new
    sitemap_urls.to_a.first(8).each do |sitemap_url|
      collect_sitemap_urls(sitemap_url, all_urls, searched, depth: 0)
    rescue StandardError
      next
    end

    direct = []
    pages = []
    all_urls.each do |url|
      text = CGI.unescape(url)
      next unless text.match?(REPORT_PATTERN)
      next if text.match?(EXCLUDE_PATTERN)

      if pdf_url?(url)
        direct << { url: url, label: File.basename(URI(url).path), source_page_url: url }
      else
        pages << url
      end
    end

    begin
      home = fetch_with_jina_fallback(root)
      links = extract_report_links(home, root)
      direct.concat(links.select { |candidate| pdf_url?(candidate.fetch(:url)) })
      pages.concat(links.reject { |candidate| pdf_url?(candidate.fetch(:url)) }.map { |candidate| candidate.fetch(:url) })
    rescue StandardError
      # A sitemap-only result remains useful.
    end

    [ pages.uniq, direct, searched ]
  end

  def collect_sitemap_urls(url, collected, searched, depth:)
    return if depth > 2 || searched.include?(url)

    body = fetch(url)
    searched << url
    document = Nokogiri::XML(body)
    locations = document.xpath("//*[local-name()='loc']").map { |node| node.text.strip }.reject(&:empty?)
    if document.at_xpath("//*[local-name()='sitemapindex']")
      locations.first(30).each { |child| collect_sitemap_urls(child, collected, searched, depth: depth + 1) }
    else
      locations.first(50_000).each { |location| collected << location }
    end
  end

  def extract_report_links(body, base_url)
    links = []
    document = Nokogiri::HTML(body)
    document.css("a[href]").each do |anchor|
      href = anchor["href"].to_s.strip
      label = anchor.text.strip
      next unless "#{label} #{href}".match?(REPORT_PATTERN)
      next if "#{label} #{href}".match?(EXCLUDE_PATTERN)

      absolute = URI.join(base_url, href).to_s
      next unless absolute.match?(/\Ahttps?:\/\//)

      links << { url: absolute, label: label, source_page_url: base_url }
    rescue URI::InvalidURIError
      next
    end
    body.scan(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/).each do |label, href|
      next unless "#{label} #{href}".match?(REPORT_PATTERN)
      next if "#{label} #{href}".match?(EXCLUDE_PATTERN)

      links << { url: href, label: label, source_page_url: base_url }
    end
    links
  end

  def classify_and_archive_bc_report(row, candidate)
    label = candidate.fetch(:label).to_s
    url = candidate.fetch(:url)
    evidence = "#{label} #{CGI.unescape(url)}"
    return if evidence.match?(EXCLUDE_PATTERN)

    type = if evidence.match?(/(?:statement[\s_-]*of[\s_-]*financial[\s_-]*information|\bsofi\b)/i)
      "statement-of-financial-information"
    elsif evidence.match?(/annual[\s_-]*(?:municipal[\s_-]*)?report/i)
      "annual-report"
    else
      "financial-statements"
    end
    year = bc_report_year(label, url)
    return unless year

    asset = archive_pdf(url)
    title_type = {
      "annual-report" => "Annual Report",
      "statement-of-financial-information" => "Statement of Financial Information",
      "financial-statements" => "Audited Financial Statements"
    }.fetch(type)
    fiscal_period = type == "annual-report" ? {} : {
      "fiscal_period_start" => "#{year}-01-01",
      "fiscal_period_end" => "#{year}-12-31"
    }
    asset.merge(
      "canonical_id" => row.fetch("canonical_id"),
      "title" => label.empty? ? "#{row.fetch('official_name')} #{title_type} — #{year}" : label,
      "document_type" => type,
      "document_variant" => "general",
      **fiscal_period,
      "published_on" => nil,
      "source_page_url" => candidate.fetch(:source_page_url),
      "download_url" => url,
      "languages" => [ "en" ],
      "retrieved_at" => @retrieved_at.iso8601,
      "rights_status" => "metadata_only",
      "notes" => "Official local-government website; document class is retained from its title and URL."
    )
  end

  def attach_statcan!(municipalities, province_code:)
    geography_rows = statcan_csd_rows(province_code)
    municipalities.each do |row|
      matches = statcan_matches(row, geography_rows, province_code: province_code)
      row["statcan_csd_uids"] = matches.map { |match| match.fetch(:uid) }
      row["statcan_geographies"] = matches.map { |match| { "uid" => match.fetch(:uid), "name" => match.fetch(:name) } }
    end
  end

  def statcan_csd_rows(province_code)
    CSV.foreach(@statcan_structure, headers: true, encoding: "Windows-1252:UTF-8").filter_map do |row|
      next unless row.fetch("Level") == "4" && row.fetch("Code").start_with?(province_code)

      { uid: row.fetch("Code"), name: row.fetch("Class title") }
    end
  end

  def statcan_matches(row, geographies, province_code:)
    uid_overrides = {
      "ca/ab/taber" => [ "4802022" ],
      "ca/ab/taber-municipal-district" => [ "4802021" ],
      "ca/bc/langley-city" => [ "5915002" ],
      "ca/bc/langley-township" => [ "5915001" ],
      "ca/bc/north-vancouver-city" => [ "5915051" ],
      "ca/bc/north-vancouver-district" => [ "5915046" ]
    }
    overridden_uids = uid_overrides[row.fetch("canonical_id")]
    return geographies.select { |candidate| overridden_uids.include?(candidate.fetch(:uid)) } if overridden_uids

    name = row["directory_name"] || row.fetch("official_name")
    target = comparable_name(name)
    matches = geographies.select { |candidate| comparable_name(candidate.fetch(:name)) == target }
    return matches unless matches.empty?

    aliases = {
      [ "48", "improvement district no 09 banff" ] => [ "Improvement District No. 9 Banff" ],
      [ "48", "clear hills county" ] => [ "Clear Hills" ],
      [ "48", "county of barrhead no 11" ] => [ "Barrhead County No. 11" ],
      [ "48", "county of forty mile no 8" ] => [ "Forty Mile County No. 8" ],
      [ "48", "county of grande prairie no 1" ] => [ "Grande Prairie County No. 1" ],
      [ "48", "county of minburn no 27" ] => [ "Minburn County No. 27" ],
      [ "48", "county of newell" ] => [ "Newell County" ],
      [ "48", "county of northern lights" ] => [ "Northern Lights County" ],
      [ "48", "county of paintearth no 18" ] => [ "Paintearth County No. 18" ],
      [ "48", "county of st paul no 19" ] => [ "St. Paul County No. 19" ],
      [ "48", "county of stettler no 6" ] => [ "Stettler County No. 6" ],
      [ "48", "county of two hills no 21" ] => [ "Two Hills County No. 21" ],
      [ "48", "county of vermilion river" ] => [ "Vermilion River County" ],
      [ "48", "county of warner no 5" ] => [ "Warner County No. 5" ],
      [ "48", "county of wetaskiwin no 10" ] => [ "Wetaskiwin County No. 10" ],
      [ "48", "diamond valley" ] => [ "Black Diamond", "Turner Valley" ],
      [ "48", "kananaskis improvement district" ] => [ "Kananaskis" ],
      [ "48", "improvement district no 12 jasper national park" ] => [ "Improvement District No. 12 Jasper Park" ],
      [ "48", "lloydminster" ] => [ "Lloydminster (Part)" ],
      [ "48", "special areas board" ] => [ "Special Area No. 2", "Special Area No. 3", "Special Area No. 4" ],
      [ "48", "improvement district no 04 waterton" ] => [ "Improvement District No. 4 Waterton" ],
      [ "48", "jasper" ] => [ "Jasper, Municipality of" ],
      [ "48", "crowsnest pass" ] => [ "Crowsnest Pass, Municipality of" ],
      [ "48", "wood buffalo" ] => [ "Wood Buffalo" ],
      [ "59", "sechelt" ] => [ "Sechelt" ],
      [ "59", "100 mile house" ] => [ "One Hundred Mile House" ],
      [ "59", "daajing giids" ] => [ "Queen Charlotte" ],
      [ "59", "sun peaks" ] => [ "Sun Peaks Mountain" ],
      [ "59", "shishalh nation government district" ] => [ "Sechelt (Part)" ]
    }
    wanted = aliases.fetch([ province_code, target ], [])
    geographies.select { |candidate| wanted.any? { |value| comparable_name(candidate.fetch(:name)) == comparable_name(value) } }
  end

  def comparable_name(value)
    value.to_s.downcase
      .unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .gsub(/\b(?:city|town|village|summer village|district|municipal district|municipality|regional municipality|resort municipality|township|island municipality) of\b/, "")
      .gsub(/\b(?:city|town|village|district municipality)\b/, "")
      .gsub(/[^a-z0-9]+/, " ").strip
  end

  def repair_geographies
    path = @output_dir.join("normalized-municipalities.json")
    payload = JSON.parse(path.read)
    rows = payload.fetch("municipalities")
    if @province == "bc"
      repair_bc_static_rows!(rows)
      payload.fetch("province")["government_name_fr"] = nil
      payload.fetch("province")["source_languages"] = [ "en" ]
      payload["roster_source_publisher"] = "CivicInfo BC"
    end
    rows.each do |row|
      row["identifiers"] = Array(row["identifiers"]).reject { |identifier| identifier["scheme"] == "statcan.csd" }
    end
    province_code = @province == "ab" ? "48" : "59"
    attach_statcan!(rows, province_code: province_code)
    write_json(path, payload)

    summary_path = @output_dir.join("scrape-summary.json")
    summary = JSON.parse(summary_path.read).merge(
      "with_statcan_geographies" => rows.count { |row| Array(row["statcan_geographies"]).any? }
    )
    write_json(summary_path, summary)
    summary
  end

  def repair_bc_static_rows!(rows)
    okanagan_falls = rows.find { |row| row["canonical_id"] == "ca/bc/okanagan-falls" }
    return unless okanagan_falls

    okanagan_falls["website_url"] = "https://engage.gov.bc.ca/govtogetherbc/engagement/okanaganfalls/"
    okanagan_falls["website_source_url"] = okanagan_falls["website_url"]
    okanagan_falls["status"] = "proposed"
    okanagan_falls["active_from"] = "2026-11-06"
    okanagan_falls["description_en"] =
      "Letters patent were issued June 24, 2026; incorporation takes effect November 6, 2026."
  end

  def normalize_bc_reports
    batch_path = @output_dir.join("financial-report-batch.json")
    batch = JSON.parse(batch_path.read)
    raw_copy = @raw_dir.join("financial-report-batch-pre-normalization.json")
    write_json(raw_copy, batch) unless raw_copy.exist?

    batch.fetch("municipalities").each do |municipality|
      %w[financial_statements annual_reports].each do |key|
        municipality[key] = Array(municipality[key]).filter_map do |report|
          evidence = "#{report['title']} #{CGI.unescape(report['download_url'].to_s)}"
          next if key == "annual_reports" && evidence.match?(NON_MUNICIPAL_REPORT_PATTERN)

          year = bc_report_year(report["title"], report["download_url"])
          next unless year

          report.merge(
            "fiscal_period_start" => "#{year}-01-01",
            "fiscal_period_end" => "#{year}-12-31"
          )
        end
      end
      report_count = Array(municipality["financial_statements"]).length + Array(municipality["annual_reports"]).length
      failure_count = Array(municipality["gaps"]).length
      municipality["gaps"] = if report_count.zero?
        [
          failure_count.positive? ?
            "No report asset was verified; #{failure_count} candidate links or report pages failed validation." :
            "No financial statements or annual reports were discovered through the official site's public sitemaps and report pages."
        ]
      elsif failure_count.positive?
        [ "#{failure_count} additional candidate links or report pages failed validation; verified assets are retained." ]
      else
        []
      end
    end
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)

    summary_path = @output_dir.join("scrape-summary.json")
    summary = JSON.parse(summary_path.read).merge(report_summary(batch.fetch("municipalities")))
    write_json(summary_path, summary)
    summary
  end

  def retry_bc_missing_reports
    base_path = @output_dir.join("normalized-municipalities.json")
    batch_path = @output_dir.join("financial-report-batch.json")
    base = JSON.parse(base_path.read)
    batch = JSON.parse(batch_path.read)
    raw_copy = @raw_dir.join("financial-report-batch-pre-bc-retry.json")
    write_json(raw_copy, batch) unless raw_copy.exist?

    report_by_id = batch.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    missing = base.fetch("municipalities").select do |row|
      report = report_by_id.fetch(row.fetch("canonical_id"))
      Array(report["financial_statements"]).empty? && Array(report["annual_reports"]).empty?
    end
    replacements = parallel_map(missing) do |row|
      if row["status"] == "proposed"
        {
          "canonical_id" => row.fetch("canonical_id"),
          "searched_locations" => [ row.fetch("website_url") ],
          "gaps" => [ "Institution is proposed at the release date and is not expected to have historical municipal reports." ],
          "financial_statements" => [],
          "annual_reports" => []
        }
      else
        retry_bc_site(row)
      end
    rescue StandardError => error
      {
        "canonical_id" => row.fetch("canonical_id"),
        "searched_locations" => [ row.fetch("website_url") ],
        "gaps" => [ "targeted municipal-site retry failed: #{error.message}" ],
        "financial_statements" => [],
        "annual_reports" => []
      }
    end

    replacements.each { |replacement| report_by_id[replacement.fetch("canonical_id")] = replacement }
    batch["municipalities"] = report_by_id.values.sort_by { |row| row.fetch("canonical_id") }
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)
    normalize_bc_reports
  end

  def add_bc_known_reports
    base = JSON.parse(@output_dir.join("normalized-municipalities.json").read)
    rows_by_id = base.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    batch_path = @output_dir.join("financial-report-batch.json")
    batch = JSON.parse(batch_path.read)
    report_by_id = batch.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }

    BC_VERIFIED_REPORTS.each do |canonical_id, candidates|
      row = rows_by_id.fetch(canonical_id)
      report_row = report_by_id.fetch(canonical_id)
      reports = candidates.filter_map { |candidate| classify_and_archive_bc_report(row, candidate) }
      report_row["financial_statements"] =
        (Array(report_row["financial_statements"]) + reports).uniq { |report| report.fetch("content_sha256") }
      report_row["gaps"] = Array(report_row["gaps"])
    end
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)
    normalize_bc_reports
  end

  def retry_bc_site(row)
    website = normalize_website(row.fetch("website_url"))
    origin = URI(website)
    unless %w[http https].include?(origin.scheme) && origin.host
      raise ScrapeError, "invalid official website #{website}"
    end

    origin.path = "/"
    origin.query = nil
    origin.fragment = nil
    root = origin.to_s
    searched = []
    candidates = []
    report_pages = Set.new

    bc_search_paths.each do |path|
      url = URI.join(root, path).to_s
      begin
        body = fetch_with_jina_fallback(url)
        searched << url
        links = extract_report_links(body, url)
        candidates.concat(links.select { |candidate| pdf_url?(candidate.fetch(:url)) })
        links.reject { |candidate| pdf_url?(candidate.fetch(:url)) }
          .each { |candidate| report_pages << candidate.fetch(:url) }
      rescue StandardError
        next
      end
    end

    brave_search_candidates(row, root, searched).each do |candidate|
      if pdf_url?(candidate.fetch(:url))
        candidates << candidate
      else
        report_pages << candidate.fetch(:url)
      end
    end

    wordpress_search_pages(root, searched).each { |page| report_pages << page }
    report_pages.to_a.first(@max_bc_pages * 2).each do |page_url|
      begin
        body = fetch_with_jina_fallback(page_url)
        searched << page_url
        candidates.concat(extract_report_links(body, page_url))
      rescue StandardError
        next
      end
    end
    candidates.uniq! { |candidate| normalized_url(candidate.fetch(:url)) }

    errors = []
    reports = candidates.filter_map do |candidate|
      classify_and_archive_bc_report(row, candidate)
    rescue StandardError => error
      errors << "#{candidate.fetch(:url)}: #{error.message}"
      nil
    end
    {
      "canonical_id" => row.fetch("canonical_id"),
      "searched_locations" => searched.uniq.sort,
      "gaps" => errors.uniq,
      "financial_statements" => reports.reject { |report| report["document_type"] == "annual-report" },
      "annual_reports" => reports.select { |report| report["document_type"] == "annual-report" }
    }
  end

  def bc_search_paths
    encoded = CGI.escape("financial statements annual report")
    [
      "/?s=#{encoded}",
      "/search?query=#{encoded}",
      "/search/node?keys=#{encoded}",
      "/Search/Results?searchPhrase=#{encoded}",
      "/Search?searchPhrase=#{encoded}",
      "/search.aspx?q=#{encoded}",
      "/financial-statements",
      "/annual-reports",
      "/city-hall/finance/financial-statements",
      "/municipal-hall/finance/financial-statements",
      "/government/finance/financial-statements",
      "/government/financial-reports"
    ]
  end

  def wordpress_search_pages(root, searched)
    %w[financial%20statements annual%20report].flat_map do |query|
      url = URI.join(root, "/wp-json/wp/v2/search?search=#{query}&per_page=100").to_s
      body = fetch(url)
      searched << url
      JSON.parse(body).filter_map do |result|
        candidate = result["url"]
        candidate if candidate.to_s.match?(/\Ahttps?:\/\//)
      end
    rescue StandardError
      []
    end.uniq
  end

  def brave_search_candidates(row, root, searched)
    official_host = URI(root).host.sub(/\Awww\./, "")
    queries = [
      %(site:#{official_host} "audited financial statements"),
      %(site:#{official_host} "annual report"),
      %(site:#{official_host} SOFI financial)
    ]
    queries.flat_map do |query|
      search_url = "https://search.brave.com/search?q=#{CGI.escape(query)}&source=web"
      body = fetch(search_url)
      searched << search_url
      Nokogiri::HTML(body).css("a[href]").filter_map do |anchor|
        href = anchor["href"].to_s
        next unless href.match?(/\Ahttps?:\/\//)

        uri = URI(href)
        candidate_host = uri.host.to_s.sub(/\Awww\./, "")
        next unless candidate_host == official_host || candidate_host.end_with?(".#{official_host}")

        label = anchor.text.strip
        {
          url: href,
          label: label.empty? ? "#{row.fetch('official_name')} report" : label,
          source_page_url: href
        }
      rescue URI::InvalidURIError
        nil
      end.first(10)
    rescue StandardError
      []
    end.uniq { |candidate| normalized_url(candidate.fetch(:url)) }
  end

  def bc_report_year(label, url)
    label_years = label.to_s.scan(/\b(20\d{2})\b/).flatten.map(&:to_i).select { |year| valid_report_year?(year) }
    return label_years.max if label_years.any?

    filename = CGI.unescape(File.basename(URI(url).path)).downcase
    patterns = [
      /annual[\s_-]*(?:municipal[\s_-]*)?report[^0-9]{0,30}(20\d{2})/,
      /financial[\s_-]*statements?[^0-9]{0,30}(20\d{2})/,
      /statement[\s_-]*of[\s_-]*financial[\s_-]*information[^0-9]{0,30}(20\d{2})/,
      /sofi[^0-9]{0,30}(20\d{2})/,
      /(20\d{2})[^0-9]{0,30}annual[\s_-]*(?:municipal[\s_-]*)?report/,
      /(20\d{2})[^0-9]{0,30}financial[\s_-]*statements?/,
      /(20\d{2})[^0-9]{0,30}(?:sofi|statement[\s_-]*of[\s_-]*financial)/
    ]
    patterns.each do |pattern|
      year = filename[pattern, 1]&.to_i
      return year if valid_report_year?(year)
    end
    filename.scan(/\b(20\d{2})\b/).flatten.map(&:to_i).select { |year| valid_report_year?(year) }.last
  rescue URI::InvalidURIError
    nil
  end

  def valid_report_year?(year)
    year && year.between?(2000, @retrieved_at.year)
  end

  def build_payload(municipalities:, report_rows:, province:, roster_url:, roster_title:, roster_publisher: nil)
    municipalities.each do |row|
      row.delete("_type_code")
      row.delete("_municipal_code")
      row.delete("contact_errors")
      row.delete("statement_errors")
      row.delete("scrape_errors")
    end
    base = {
      "release_version" => @retrieved_at.to_date.iso8601,
      "effective_on" => @retrieved_at.to_date.iso8601,
      "source_retrieved_at" => @retrieved_at.iso8601,
      "geography_vintage" => 2021,
      "province" => province,
      "roster_source_url" => roster_url,
      "roster_source_title" => roster_title,
      "roster_source_publisher" => roster_publisher || province.fetch("government_name_en"),
      "geography_source_url" => STATCAN_URL,
      "municipalities" => municipalities.sort_by { |row| row.fetch("canonical_id") }
    }
    batch = {
      "batch" => "#{province.fetch('code')}-municipal-financial-reports",
      "retrieved_at" => @retrieved_at.iso8601,
      "municipalities" => report_rows.sort_by { |row| row.fetch("canonical_id") },
      "summary" => report_summary(report_rows)
    }
    summary = report_summary(report_rows).merge(
      "province" => province.fetch("code"),
      "municipalities" => municipalities.length,
      "with_websites" => municipalities.count { |row| !row["website_url"].to_s.empty? },
      "with_statcan_geographies" => municipalities.count { |row| Array(row["statcan_geographies"]).any? },
      "retrieved_at" => @retrieved_at.iso8601
    )
    { base: base, batch: batch, summary: summary }
  end

  def report_summary(report_rows)
    documents = report_rows.flat_map do |row|
      Array(row["financial_statements"]) + Array(row["annual_reports"])
    end
    {
      "financial_statement_assets" => documents.count { |row| row["document_type"] == "financial-statements" },
      "statement_of_financial_information_assets" => documents.count do |row|
        row["document_type"] == "statement-of-financial-information"
      end,
      "annual_report_assets" => documents.count { |row| row["document_type"] == "annual-report" },
      "municipalities_with_reports" => report_rows.count do |row|
        Array(row["financial_statements"]).any? || Array(row["annual_reports"]).any?
      end,
      "municipalities_with_gaps" => report_rows.count { |row| Array(row["gaps"]).any? }
    }
  end

  def repair_alberta_contacts
    path = @output_dir.join("normalized-municipalities.json")
    payload = JSON.parse(path.read)
    profile_url = "https://municipalaffairs.gov.ab.ca/cfml/MunicipalProfiles/index"
    type_codes = ALBERTA_TYPES.invert
    rows = payload.fetch("municipalities")
    rows.each do |row|
      row["_type_code"] = type_codes.fetch(row.fetch("municipality_type"))
      row["_municipal_code"] = Array(row.fetch("identifiers")).find do |identifier|
        identifier["scheme"] == "ab.municipal_code"
      end.fetch("value")
      row["website_url"] = nil
      row["contact"] = {}
      row["contact_errors"] = []
    end
    parallel_each(rows) do |row|
      enrich_alberta_contact!(row, profile_url)
    rescue StandardError => error
      row["contact_errors"] << "contact profile: #{error.message}"
      row["website_url"] = fallback_alberta_website(row)
    end
    unresolved = rows.count { |row| Array(row["contact_errors"]).any? }
    rows.each do |row|
      row.delete("_type_code")
      row.delete("_municipal_code")
      row.delete("contact_errors")
    end
    write_json(path, payload)

    batch_path = @output_dir.join("financial-report-batch.json")
    batch = JSON.parse(batch_path.read)
    batch.fetch("municipalities").each do |row|
      row["gaps"] = Array(row["gaps"]).reject { |gap| gap.start_with?("contact profile:") }
    end
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)

    summary_path = @output_dir.join("scrape-summary.json")
    summary = JSON.parse(summary_path.read).merge(
      "with_websites" => rows.count { |row| !row["website_url"].to_s.empty? },
      "contact_profiles_unresolved" => unresolved
    )
    summary.merge!(report_summary(batch.fetch("municipalities")))
    write_json(summary_path, summary)
    summary
  end

  def retry_alberta_report_gaps
    base = JSON.parse(@output_dir.join("normalized-municipalities.json").read)
    batch_path = @output_dir.join("financial-report-batch.json")
    batch = JSON.parse(batch_path.read)
    batch_by_id = batch.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    type_codes = ALBERTA_TYPES.invert
    retry_rows = base.fetch("municipalities").filter_map do |row|
      next if Array(batch_by_id.fetch(row.fetch("canonical_id"))["gaps"]).empty?

      row.merge(
        "_type_code" => type_codes.fetch(row.fetch("municipality_type")),
        "statement_errors" => []
      )
    end
    replacements = parallel_map(retry_rows) do |row|
      scrape_alberta_statements(row, "https://municipalaffairs.gov.ab.ca/mc_financial_tax_bylaws.cfm")
    end
    replacements.each { |row| batch_by_id[row.fetch("canonical_id")] = row }
    batch["municipalities"] = batch_by_id.values.sort_by { |row| row.fetch("canonical_id") }
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)

    summary_path = @output_dir.join("scrape-summary.json")
    summary = JSON.parse(summary_path.read).merge(report_summary(batch.fetch("municipalities")))
    write_json(summary_path, summary)
    summary
  end

  def repair_alberta_canonical_collisions
    base_path = @output_dir.join("normalized-municipalities.json")
    base = JSON.parse(base_path.read)
    collision_ids = base.fetch("municipalities").group_by { |row| row.fetch("canonical_id") }
      .select { |_canonical_id, rows| rows.length > 1 }.keys
    return JSON.parse(@output_dir.join("scrape-summary.json").read) if collision_ids.empty?

    affected = base.fetch("municipalities").select { |row| collision_ids.include?(row.fetch("canonical_id")) }
    resolve_canonical_collisions!(affected)
    type_codes = ALBERTA_TYPES.invert
    affected.each do |row|
      row["_type_code"] = type_codes.fetch(row.fetch("municipality_type"))
      row["statement_errors"] = []
    end
    replacements = parallel_map(affected) do |row|
      scrape_alberta_statements(row, "https://municipalaffairs.gov.ab.ca/mc_financial_tax_bylaws.cfm")
    end
    affected.each { |row| row.delete("_type_code"); row.delete("statement_errors") }
    write_json(base_path, base)

    batch_path = @output_dir.join("financial-report-batch.json")
    batch = JSON.parse(batch_path.read)
    batch["municipalities"].reject! { |row| collision_ids.include?(row.fetch("canonical_id")) }
    batch["municipalities"].concat(replacements)
    batch["municipalities"].sort_by! { |row| row.fetch("canonical_id") }
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)

    summary_path = @output_dir.join("scrape-summary.json")
    summary = JSON.parse(summary_path.read).merge(report_summary(batch.fetch("municipalities")))
    write_json(summary_path, summary)
    summary
  end

  def repair_bc_canonical_collisions
    base_path = @output_dir.join("normalized-municipalities.json")
    base = JSON.parse(base_path.read)
    rows = base.fetch("municipalities")
    collisions = rows.group_by { |row| row.fetch("canonical_id") }
      .select { |_canonical_id, matches| matches.length > 1 }
    return recover_bc_collision_reports!(rows) if collisions.empty?

    replacements = {}
    collisions.each do |old_id, matches|
      matches.each do |row|
        new_id = "#{old_id}-#{slugify(row.fetch('municipality_type'))}"
        replacements[[ old_id, URI(normalize_website(row.fetch("website_url"))).host.sub(/\Awww\./, "") ]] = new_id
        row["canonical_id"] = new_id
      end
    end
    write_json(base_path, base)

    batch_path = @output_dir.join("financial-report-batch.json")
    batch = JSON.parse(batch_path.read)
    collisions.each_key do |old_id|
      report_rows = batch.fetch("municipalities").select { |row| row["canonical_id"] == old_id }
      report_rows.each do |report_row|
        searched_hosts = Array(report_row["searched_locations"]).filter_map do |url|
          URI(url).host&.sub(/\Awww\./, "")
        rescue URI::InvalidURIError
          nil
        end
        match = replacements.find do |(candidate_id, host), _new_id|
          candidate_id == old_id && searched_hosts.any? do |searched_host|
            searched_host == host || searched_host.end_with?(".#{host}") || host.end_with?(".#{searched_host}")
          end
        end
        raise ScrapeError, "could not disambiguate report row for #{old_id}" unless match

        report_row["canonical_id"] = match.last
        %w[financial_statements annual_reports].each do |key|
          Array(report_row[key]).each { |report| report["canonical_id"] = match.last }
        end
      end
    end
    batch.fetch("municipalities").sort_by! { |row| row.fetch("canonical_id") }
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)
    recover_bc_collision_reports!(rows)
  end

  def recover_bc_collision_reports!(base_rows)
    raw_path = @raw_dir.join("financial-report-batch-pre-bc-retry.json")
    batch_path = @output_dir.join("financial-report-batch.json")
    batch = JSON.parse(batch_path.read)
    return batch.fetch("summary") unless raw_path.exist?

    current_ids = batch.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), true ] }
    raw_rows = JSON.parse(raw_path.read).fetch("municipalities")
    base_rows.each do |base_row|
      canonical_id = base_row.fetch("canonical_id")
      next if current_ids[canonical_id]
      next unless canonical_id.match?(/-(?:city|district|township)\z/)

      old_id = canonical_id.sub(/-(?:city|district|township)\z/, "")
      official_host = URI(normalize_website(base_row.fetch("website_url"))).host.sub(/\Awww\./, "")
      raw_row = raw_rows.find do |candidate|
        candidate["canonical_id"] == old_id && Array(candidate["searched_locations"]).any? do |url|
          host = URI(url).host&.sub(/\Awww\./, "")
          host == official_host || host&.end_with?(".#{official_host}") || official_host.end_with?(".#{host}")
        rescue URI::InvalidURIError
          false
        end
      end
      next unless raw_row

      recovered = Marshal.load(Marshal.dump(raw_row))
      recovered["canonical_id"] = canonical_id
      %w[financial_statements annual_reports].each do |key|
        Array(recovered[key]).each { |report| report["canonical_id"] = canonical_id }
      end
      batch.fetch("municipalities") << recovered
      current_ids[canonical_id] = true
    end
    batch.fetch("municipalities").sort_by! { |row| row.fetch("canonical_id") }
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(batch_path, batch)

    summary_path = @output_dir.join("scrape-summary.json")
    summary = JSON.parse(summary_path.read).merge(batch.fetch("summary"))
    write_json(summary_path, summary)
    summary
  end

  def resolve_bc_canonical_collisions!(rows)
    rows.group_by { |row| row.fetch("canonical_id") }.each_value do |matches|
      next if matches.one?

      matches.each do |row|
        row["canonical_id"] = "#{row.fetch('canonical_id')}-#{slugify(row.fetch('municipality_type'))}"
      end
    end
  end

  def resolve_canonical_collisions!(rows)
    rows.group_by { |row| row.fetch("canonical_id") }.each_value do |collisions|
      next if collisions.one?

      keeper = collisions.min_by do |row|
        %w[City Town Village Summer\ Village].index(row.fetch("municipality_type")) || 100
      end
      (collisions - [ keeper ]).each do |row|
        row["canonical_id"] = "#{row.fetch('canonical_id')}-#{slugify(row.fetch('municipality_type'))}"
      end
    end
  end

  def source_record(url:, publisher:, title:, license: nil)
    {
      "url" => url,
      "publisher_name" => publisher,
      "title" => title,
      "retrieved_at" => @retrieved_at.iso8601,
      "languages" => [ "en" ],
      "license" => license,
      "attribution" => nil
    }
  end

  def institution_slug(official_name, legal_form)
    name = official_name.sub(/\A(?:City|Town|Village|Summer Village|Municipal District) of\s+/i, "")
    if legal_form == "Improvement District"
      number = name[/No\.\s*0*(\d+)/i, 1]
      place = name[/\(([^)]+)\)/, 1]
      parsed = slugify([ place, "improvement district", number ].compact.join(" "))
      return parsed unless parsed == "improvement-district"

      return slugify(name)
    end
    slugify(name)
  end

  def slugify(value)
    value.to_s.downcase.unicode_normalize(:nfkd)
      .encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .gsub(/['’]/, "").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
  end

  def normalize_website(value)
    website = value.to_s.strip
    return website if website.match?(/\Ahttps?:\/\//)

    "https://#{website}"
  end

  def normalized_url(value)
    uri = URI(value)
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    value
  end

  def pdf_url?(url)
    URI(url).path.downcase.end_with?(".pdf")
  rescue URI::InvalidURIError
    false
  end

  def archive_pdf(url)
    bytes = fetch(url, max_bytes: 100 * 1024 * 1024)
    raise ScrapeError, "response is not a PDF" unless bytes.start_with?("%PDF-")

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

  def fetch_with_jina_fallback(url)
    fetch(url)
  rescue StandardError
    uri = URI(url)
    fetch("https://r.jina.ai/http://#{uri.host}#{uri.request_uri}")
  end

  def fetch(url, redirects: 8, max_bytes: 20 * 1024 * 1024)
    raise ScrapeError, "too many redirects for #{url}" if redirects.negative?

    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "*/*"
    response = request_with_retries(uri, request)
    case response
    when Net::HTTPSuccess
      body = response.body
      raise ScrapeError, "response exceeds #{max_bytes} bytes" if body.bytesize > max_bytes
      body
    when Net::HTTPRedirection
      fetch(URI.join(url, response.fetch("location")).to_s, redirects: redirects - 1, max_bytes: max_bytes)
    else
      raise ScrapeError, "HTTP #{response.code} for #{url}"
    end
  end

  def post_form(url, fields)
    uri = URI(url)
    request = Net::HTTP::Post.new(uri)
    request["User-Agent"] = USER_AGENT
    request.set_form_data(fields)
    response = request_with_retries(uri, request)
    raise ScrapeError, "HTTP #{response.code} for #{url}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def request_with_retries(uri, request)
    attempts = 0
    begin
      attempts += 1
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 15,
        read_timeout: 90
      ) { |http| http.request(request) }
    rescue IOError, SystemCallError, Timeout::Error, Net::HTTPError => error
      retry if attempts < 3
      raise ScrapeError, "#{error.class}: #{error.message}"
    end
  end

  def parallel_each(rows, &block)
    parallel_map(rows, &block)
    rows
  end

  def parallel_map(rows, &block)
    queue = Queue.new
    rows.each_with_index { |row, index| queue << [ index, row ] }
    results = Array.new(rows.length)
    workers = [ @threads, rows.length ].min.times.map do
      Thread.new do
        loop do
          index, row = queue.pop(true)
          results[index] = block.call(row)
        rescue ThreadError
          break
        end
      end
    end
    workers.each(&:join)
    results
  end

  def write_json(path, object)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(object) << "\n")
  end
end

options = {
  threads: 8,
  max_bc_pages: 40
}
parser = OptionParser.new do |opts|
  opts.banner = "usage: #{$PROGRAM_NAME} --province ab|bc --output-dir PATH --retrieved-at TIME [options]"
  opts.on("--province CODE", %w[ab bc], "Province code") { |value| options[:province] = value }
  opts.on("--output-dir PATH", "Source-package directory on the external drive") { |value| options[:output_dir] = value }
  opts.on("--retrieved-at TIME", "Frozen ISO-8601 retrieval timestamp") { |value| options[:retrieved_at] = value }
  opts.on("--threads COUNT", Integer, "Concurrent municipalities (default: 8)") { |value| options[:threads] = value }
  opts.on("--asset-root PATH", "Content-addressed PDF store") { |value| options[:asset_root] = value }
  opts.on("--statcan-structure PATH", "Statistics Canada 2021 SGC structure CSV") do |value|
    options[:statcan_structure] = value
  end
  opts.on("--max-bc-pages COUNT", Integer, "Maximum candidate pages per BC municipality") do |value|
    options[:max_bc_pages] = value
  end
  opts.on("--contacts-only", "Repair Alberta contact profiles without re-downloading reports") do
    options[:contacts_only] = true
  end
  opts.on("--retry-gaps", "Retry only Alberta municipalities whose report batch records gaps") do
    options[:retry_gaps] = true
  end
  opts.on("--repair-collisions", "Repair semantic-ID collisions without re-downloading unaffected records") do
    options[:repair_collisions] = true
  end
  opts.on("--repair-geographies", "Recompute Statistics Canada CSD associations without re-scraping") do
    options[:repair_geographies] = true
  end
  opts.on("--normalize-bc-reports", "Correct BC report years, remove service-level reports, and summarize gaps") do
    options[:normalize_bc_reports] = true
  end
  opts.on("--retry-bc-missing", "Targeted search retry for BC municipalities with no verified reports") do
    options[:retry_bc_missing] = true
  end
  opts.on("--add-bc-known-reports", "Archive reviewed BC report URLs missed by automated discovery") do
    options[:add_bc_known_reports] = true
  end
end
parser.parse!

if $PROGRAM_NAME == __FILE__
  abort parser.to_s unless options.values_at(:province, :output_dir, :retrieved_at).all?

  summary = WesternMunicipalFinancialReportScraper.new(**options).call
  puts JSON.pretty_generate(summary)
end
