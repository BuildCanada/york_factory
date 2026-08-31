#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "csv"
require "date"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "openssl"
require "optparse"
require "pathname"
require "set"
require "time"
require "uri"

# Builds a dated, reproducible BC augmentation without changing the shared
# ontology importer. The output contains the original 162 CivicInfo municipal
# records, all regional districts and Islands Trust, geography associations,
# evidence-backed membership edges, and archived official report assets.
class BcRegionalDistrictAugmenter
  USER_AGENT = "BuildCanada-YorkFactory/1.0 (+https://buildcanada.ca)".freeze
  CIVICINFO_ROSTER = "https://www.civicinfo.bc.ca/regionaldistricts".freeze
  CIVICINFO_DIRECTORIES = "https://www.civicinfo.bc.ca/directories".freeze
  RELEASE_DATE = "2026-08-21".freeze
  RELEASE_PUBLISHED_AT = "2026-08-21T12:00:00Z".freeze
  STATCAN_SOURCE = "https://www.statcan.gc.ca/en/subjects/standard/sgc/2021/index".freeze
  BC_VOTING_STRENGTH_SOURCE = "https://www2.gov.bc.ca/gov/content/governments/local-governments/governance-powers/councils-boards/board-organization/voting-strength".freeze
  SHISHALH_OLD_ID = "ca/fn/shishalh-nation-government-district".freeze
  SHISHALH_NEW_ID = "ca/bc/shishalh-nation-government-district".freeze
  REPORT_PATTERN = /(?:\bsofi\b|statement[\s_-]+of[\s_-]+financial[\s_-]+information|audited[^\n]{0,50}financial|financial[\s_-]+statements?|annual[\s_-]+(?:municipal[\s_-]+)?report)/i
  EXCLUDE_PATTERN = /(?:budget|agenda|minutes|quarterly|monthly|water[\s_-]+quality|drinking[\s_-]+water|election|public[\s_-]+notice|procurement|tender|financial[\s_-]+plan|five[\s_-]+year)/i
  SITEMAP_LOC_PATTERN = /<loc>\s*(.*?)\s*<\/loc>/im
  COMMON_REPORT_PATHS = %w[
    /annual-reports
    /annual-report
    /financial-statements
    /financial-reports
    /statement-of-financial-information
    /sofi
    /government/financial-reports
    /government/finance/financial-statements
    /about/financial-statements
    /administration/finance
  ].freeze
  CD_NAME_ALIASES = {
    "Columbia Shuswap" => "Columbia-Shuswap",
    "Metro Vancouver" => "Greater Vancouver",
    "North Coast" => "Skeena-Queen Charlotte",
    "qathet" => "Powell River"
  }.freeze
  MEMBERSHIP_NAME_ALIASES = {
    "Sun Peaks" => "Sun Peaks Mountain",
    "shíshálh Nation Government District" => "Sechelt"
  }.freeze

  def initialize(base_dir:, output_dir:, asset_root:, statcan_csv:, threads: 8, max_pages: 60, max_documents: 160)
    @base_dir = Pathname(base_dir)
    @output_dir = Pathname(output_dir)
    @asset_root = Pathname(asset_root)
    @statcan_csv = Pathname(statcan_csv)
    @threads = threads
    @max_pages = max_pages
    @max_documents = max_documents
    @retrieved_at = Time.now.utc
    @raw_dir = @output_dir.join("raw")
    @mutex = Mutex.new
  end

  def run
    validate_inputs!
    FileUtils.mkdir_p(@raw_dir)
    FileUtils.mkdir_p(@asset_root)

    base = read_json(@base_dir.join("normalized-municipalities.json"))
    batch = read_json(@base_dir.join("financial-report-batch.json"))
    previous_release = read_json(@base_dir.join("release-manifest.json"))

    roster_pages = fetch_roster_pages
    regional_rows = parse_roster(roster_pages)
    raise "expected 28 regional-district directory records, got #{regional_rows.length}" unless regional_rows.length == 28

    transform_existing_rows!(base.fetch("municipalities"))
    transform_existing_batch!(batch.fetch("municipalities"))
    transform_existing_release!(previous_release.fetch("municipalities"))
    attach_census_divisions!(regional_rows)

    relationships, membership_gaps = fetch_memberships(base.fetch("municipalities"), regional_rows)
    regional_reports = parallel_map(regional_rows) do |row|
      checkpoint_path = report_checkpoint_path(row)
      if checkpoint_path.file?
        read_json(checkpoint_path)
      else
        scrape_reports(row).tap { |result| write_json(checkpoint_path, result) }
      end
    end

    base["municipalities"].concat(regional_rows)
    base["municipalities"].sort_by! { |row| row.fetch("canonical_id") }
    update_base_metadata!(base)

    batch["municipalities"].concat(regional_reports)
    batch["municipalities"].sort_by! { |row| row.fetch("canonical_id") }
    batch["batch"] = "bc-public-institution-financial-reports"
    batch["retrieved_at"] = @retrieved_at.iso8601
    batch["summary"] = report_summary(batch.fetch("municipalities"))

    normalized_path = @output_dir.join("normalized-municipalities.json")
    batch_path = @output_dir.join("financial-report-batch.json")
    relationships_path = @output_dir.join("relationships.json")
    write_json(normalized_path, base)
    write_json(batch_path, batch)
    write_json(relationships_path, relationships_payload(relationships, membership_gaps))

    release = build_release(previous_release, base, batch, relationships, normalized_path, batch_path, relationships_path)
    write_json(@output_dir.join("release-manifest.json"), release)

    summary = build_summary(base, batch, relationships, membership_gaps, regional_reports)
    write_json(@output_dir.join("scrape-summary.json"), summary)
    write_json(@raw_dir.join("membership-gaps.json"), membership_gaps)
    copy_statcan_source
    summary
  end

  # Rebuilds only relationship evidence and the affected manifests. This is
  # useful when an upstream profile service rate-limits a long source run.
  def repair_memberships
    base_path = @output_dir.join("normalized-municipalities.json")
    batch_path = @output_dir.join("financial-report-batch.json")
    relationships_path = @output_dir.join("relationships.json")
    release_path = @output_dir.join("release-manifest.json")
    summary_path = @output_dir.join("scrape-summary.json")
    base = read_json(base_path)
    batch = read_json(batch_path)
    release = read_json(release_path)
    normalize_output_contract!(base, batch, release)
    regional_rows = base.fetch("municipalities").select { |row| %w[regional_district islands_trust].include?(row["jurisdiction_kind"]) }
    municipalities = base.fetch("municipalities").select { |row| %w[municipality government_district].include?(row["jurisdiction_kind"]) }
    relationships, gaps = fetch_memberships(municipalities, regional_rows)

    base.delete("relationships")
    base.delete("coverage")
    write_json(base_path, base)
    write_json(batch_path, batch)
    write_json(relationships_path, relationships_payload(relationships, gaps))

    release["relationships"] = relationships
    release["coverage"] = coverage_rows(release.fetch("municipalities"), relationships)
    release["raw_input_files"] = [ base_path, batch_path, relationships_path ].map { |path| file_record(path) }
    release["scrape_audit"]["batches"] = [ file_record(batch_path).merge(
      "batch" => read_json(batch_path).fetch("batch"),
      "retrieved_at" => read_json(batch_path).fetch("retrieved_at")
    ) ]
    write_json(release_path, release)

    summary = read_json(summary_path)
    summary["member_of_relationships"] = relationships.length
    summary["membership_evidence_gaps"] = gaps.length
    summary.merge!(release_document_summary(release.fetch("municipalities")))
    write_json(summary_path, summary)
    write_json(@raw_dir.join("membership-gaps.json"), gaps)
    { "member_of_relationships" => relationships.length, "membership_evidence_gaps" => gaps.length }
  end

  private

  def normalize_output_contract!(base, batch, release)
    base.fetch("municipalities").each { |row| normalize_emitted_institution!(row) }
    release.fetch("municipalities").each do |row|
      normalize_emitted_institution!(row)
      Array(row["documents"]).each { |document| normalize_emitted_document!(document) }
    end
    batch.fetch("municipalities").each do |row|
      %w[financial_statements annual_reports sofi_documents].each do |key|
        Array(row[key]).each { |document| normalize_emitted_document!(document) }
      end
    end
    update_base_metadata!(base)
    update_release_metadata!(release)
    release["schema_version"] = "1.0"
  end

  def normalize_emitted_institution!(row)
    row["jurisdiction_kind"] ||= case row["institution_type"]
    when "regional_district" then "regional_district"
    when "islands_trust" then "islands_trust"
    else row["canonical_id"] == SHISHALH_NEW_ID ? "government_district" : "municipality"
    end
    row["institution_type"] = "government"
    Array(row["statcan_geographies"]).each do |geography|
      geography["boundary_type"] = %w[cd census_division].include?(geography["boundary_type"].to_s) ? "cd" : "csd"
      geography["role"] = "governs"
    end
  end

  def normalize_emitted_document!(document)
    return unless document["document_type"] == "sofi" || document["canonical_id"].to_s.include?("/documents/sofi/")
    document["document_type"] = "statement-of-financial-information"
    document["canonical_id"] = document["canonical_id"].sub("/documents/sofi/", "/documents/statement-of-financial-information/") if document["canonical_id"]
  end

  def validate_inputs!
    %w[normalized-municipalities.json financial-report-batch.json release-manifest.json].each do |name|
      raise "missing base input #{@base_dir.join(name)}" unless @base_dir.join(name).file?
    end
    raise "missing Statistics Canada input #{@statcan_csv}" unless @statcan_csv.file?
    if @output_dir.exist? && @output_dir.children.any? && @output_dir.children.any? { |path| path.file? }
      raise "output directory is not empty: #{@output_dir}"
    end
  end

  def fetch_roster_pages
    (1..2).map do |page|
      url = "https://r.jina.ai/http://www.civicinfo.bc.ca/regionaldistricts?pn=#{page}&refresh=#{date_token}"
      body = fetch(url)
      @raw_dir.join("civicinfo-regionaldistricts-page-#{page}.md").binwrite(body)
      body
    end
  end

  def parse_roster(pages)
    entry_pattern = /(?:\A|\n)(\d+)\.\s+.*?\[\*\*(.+?)\*\*\]\([^\n]*?id=(\d+)[^)]*\)\s*\n(.*?)\n\nPh:\s*([^\n]+)\n\n(.*?)(?=\n\d+\.\s+|\n\*\s+\[(?:< Previous|Next >)|\z)/m
    pages.flat_map do |markdown|
      markdown.dup.force_encoding(Encoding::UTF_8).scrub.scan(entry_pattern).map do |_position, display_name, id, address, phone, remainder|
        name, directory_type = display_name.match(/\A(.+) \(([^)]+)\)\z/)&.captures || [ display_name, "Regional District" ]
        website = remainder.scan(/\[(https?:\/\/[^\]]+)\]\((https?:\/\/[^)]+)\)/).flatten
          .find { |url| !url.include?("civicinfo.bc.ca") && !url.include?("amazonaws.com") }
        email = remainder[/\[([^\]]+@[^\]]+)\]\(mailto:/, 1]
        raise "CivicInfo regional entry #{name} has no website" unless website

        regional_row(name, directory_type, id, address, phone, email, website)
      end
    end.uniq { |row| civicinfo_id(row) }.sort_by { |row| row.fetch("canonical_id") }
  end

  def regional_row(name, directory_type, id, address, phone, email, website)
    islands_trust = directory_type == "Islands Trust"
    canonical_id = islands_trust ? "ca/bc/islands-trust" : "ca/bc/#{slugify(name)}-regional-district"
    {
      "official_name" => islands_trust ? "Islands Trust" : "#{name} Regional District",
      "directory_name" => name,
      "municipality_type" => directory_type,
      "institution_type" => "government",
      "jurisdiction_kind" => islands_trust ? "islands_trust" : "regional_district",
      "government_level" => "regional",
      "website_url" => website,
      "website_source_url" => "https://www.civicinfo.bc.ca/regionaldistricts?id=#{id}",
      "contact" => {
        "mailing_address" => address.strip,
        "phone" => phone.strip,
        "email" => email
      }.compact,
      "canonical_id" => canonical_id,
      "identifiers" => [ {
        "scheme" => "civicinfo.bc.organization",
        "value" => id.to_s,
        "preferred" => true,
        "source_url" => CIVICINFO_ROSTER
      } ],
      "statcan_geographies" => [],
      "financial_statements" => [],
      "annual_reports" => [],
      "sofi_documents" => [],
      "sources" => [ source_record(CIVICINFO_ROSTER, "CivicInfo BC", "British Columbia Regional Districts & Islands Trust Directory") ]
    }
  end

  def transform_existing_rows!(rows)
    rows.each do |row|
      replace_shishalh_id!(row)
      row["government_level"] = "municipal" if row["canonical_id"] == SHISHALH_NEW_ID
      row["institution_type"] = "government"
      row["jurisdiction_kind"] ||= "municipality"
      row["jurisdiction_kind"] = "government_district" if row["canonical_id"] == SHISHALH_NEW_ID
      row["identifiers"] = Array(row["identifiers"]).reject { |identifier| identifier.fetch("scheme", "").start_with?("statcan.") }
      row.delete("statcan_csd_uids")
      row["statcan_geographies"] = Array(row["statcan_geographies"]).map do |geography|
        geography.merge(
          "scheme" => "statcan.sgc",
          "boundary_type" => "csd",
          "role" => "governs",
          "vintage" => 2021,
          "source_url" => STATCAN_SOURCE
        )
      end
      row["sofi_documents"] ||= []
    end
  end

  def transform_existing_batch!(rows)
    rows.each do |row|
      replace_shishalh_id!(row)
      %w[financial_statements annual_reports sofi_documents].each do |key|
        row[key] ||= []
        Array(row[key]).each { |document| replace_shishalh_id!(document) }
      end
    end
  end

  def transform_existing_release!(rows)
    rows.each do |row|
      replace_shishalh_id!(row)
      row["government_level"] = "municipal" if row["canonical_id"] == SHISHALH_NEW_ID
      row["institution_type"] = "government"
      row["jurisdiction_kind"] ||= "municipality"
      row["jurisdiction_kind"] = "government_district" if row["canonical_id"] == SHISHALH_NEW_ID
      row["identifiers"] = Array(row["identifiers"]).reject { |identifier| identifier.fetch("scheme", "").start_with?("statcan.") }
      row.delete("statcan_csd_uids")
      row["statcan_geographies"] = Array(row["statcan_geographies"]).map do |geography|
        geography.merge(
          "scheme" => "statcan.sgc",
          "boundary_type" => "csd",
          "role" => "governs",
          "vintage" => 2021,
          "source_url" => STATCAN_SOURCE
        )
      end
      Array(row["documents"]).each { |document| replace_shishalh_id!(document) }
    end
  end

  def replace_shishalh_id!(object)
    object.each do |key, value|
      next unless value.is_a?(String)
      object[key] = value.sub(SHISHALH_OLD_ID, SHISHALH_NEW_ID)
    end
  end

  def attach_census_divisions!(regional_rows)
    divisions = CSV.foreach(@statcan_csv, headers: true, encoding: "Windows-1252:UTF-8").filter_map do |row|
      next unless row["Level"] == "3" && row["Code"].to_s.start_with?("59")
      { "uid" => row["Code"], "name" => row["Class title"] }
    end
    regional_rows.each do |row|
      next if row["jurisdiction_kind"] == "islands_trust"
      lookup = CD_NAME_ALIASES.fetch(row.fetch("directory_name"), row.fetch("directory_name"))
      match = divisions.find { |division| normalize_name(division.fetch("name")) == normalize_name(lookup) }
      next unless match
      row["statcan_geographies"] << match.merge(
        "scheme" => "statcan.sgc",
        "boundary_type" => "cd",
        "role" => "governs",
        "vintage" => 2021,
        "source_url" => STATCAN_SOURCE
      )
    end
  end

  def fetch_memberships(municipalities, regional_rows)
    provincial_relationships = fetch_provincial_memberships(municipalities, regional_rows)
    resolved_ids = provincial_relationships.map { |row| row.fetch("source_id") }.to_set
    remaining = municipalities.reject { |row| resolved_ids.include?(row.fetch("canonical_id")) }
    civic_relationships, civic_gaps = fetch_civicinfo_memberships(remaining, regional_rows)
    relationships = (provincial_relationships + civic_relationships).uniq do |row|
      [ row.fetch("relationship_type"), row.fetch("source_id"), row.fetch("target_id") ]
    end
    [ relationships.sort_by { |row| row.fetch("source_id") }, civic_gaps ]
  end

  def fetch_provincial_memberships(municipalities, regional_rows)
    page = fetch(BC_VOTING_STRENGTH_SOURCE, max_bytes: 15 * 1024 * 1024)
    @raw_dir.join("bc-regional-district-voting-strength.html").binwrite(page)
    links = page.scan(/<a\b[^>]*href=["']([^"']+\.pdf)["'][^>]*>([^<]*\(PDF[^<]*)<\/a>/im).map do |url, label|
      [ CGI.unescapeHTML(label).sub(/\s*\(PDF.*\z/i, "").strip, CGI.unescapeHTML(url) ]
    end.uniq
    regional_by_name = regional_rows.select { |row| row["jurisdiction_kind"] == "regional_district" }.to_h do |row|
      [ normalize_name(row.fetch("directory_name")), row ]
    end
    relationships = []
    links.each do |label, url|
      regional = regional_by_name[normalize_name(label)]
      next unless regional
      pdf_path = @raw_dir.join("voting-strength", "#{slugify(label)}.pdf")
      text_path = pdf_path.sub_ext(".txt")
      FileUtils.mkdir_p(pdf_path.dirname)
      unless pdf_path.file?
        begin
          bytes = fetch(url, max_bytes: 10 * 1024 * 1024)
          raise "response is not a PDF" unless bytes.start_with?("%PDF-")
          pdf_path.binwrite(bytes)
        rescue StandardError
          _stdout, stderr, status = Open3.capture3(
            "curl", "--location", "--fail", "--silent", "--show-error", "--max-time", "60",
            "--output", pdf_path.to_s, url
          )
          raise "curl failed for #{url}: #{stderr}" unless status.success? && pdf_path.binread(5) == "%PDF-"
        end
      end
      _stdout, stderr, status = Open3.capture3("pdftotext", "-layout", pdf_path.to_s, text_path.to_s)
      raise "pdftotext failed for #{url}: #{stderr}" unless status.success?
      text = text_path.read
      municipalities.each do |municipality|
        name = MEMBERSHIP_NAME_ALIASES.fetch(municipality.fetch("directory_name"), municipality.fetch("directory_name"))
        member_line = text.lines.find { |line| line.match?(/^\s*#{Regexp.escape(name)}\s+[\d,]+\s+\d+/i) }
        next unless member_line
        next if member_line.match?(/\s-\s/)
        relationships << {
          "relationship_type" => "member_of",
          "source_id" => municipality.fetch("canonical_id"),
          "target_id" => regional.fetch("canonical_id"),
          "source_url" => url,
          "source_page_url" => BC_VOTING_STRENGTH_SOURCE,
          "source_publisher" => "Province of British Columbia",
          "retrieved_at" => @retrieved_at.iso8601,
          "notes" => "The official regional-district voting-strength schedule enumerates the municipality as a represented member. Evidence: #{url}"
        }
      end
    rescue StandardError
      next
    end
    relationships
  end

  def fetch_civicinfo_memberships(municipalities, regional_rows)
    by_civicinfo_id = regional_rows.to_h { |row| [ civicinfo_id(row), row ] }
    gaps = []
    relationships = parallel_map(municipalities) do |municipality|
      identifier = Array(municipality["identifiers"]).find { |item| item["scheme"] == "civicinfo.bc.organization" }
      unless identifier
        @mutex.synchronize { gaps << { "canonical_id" => municipality.fetch("canonical_id"), "reason" => "No CivicInfo organization identifier." } }
        next
      end

      civic_id = identifier.fetch("value")
      source_url = "https://www.civicinfo.bc.ca/municipalities?id=#{civic_id}"
      bodies = membership_profile_bodies(civic_id)
      regional_id = bodies.filter_map { |body| body[/regionaldistricts\?id=(\d+)/i, 1] }.first
      unless regional_id && by_civicinfo_id[regional_id]
        @mutex.synchronize do
          gaps << {
            "canonical_id" => municipality.fetch("canonical_id"),
            "source_url" => source_url,
            "reason" => regional_id ? "CivicInfo linked an unrecognized regional-district id #{regional_id}." : "No regional-district record link was present in the CivicInfo profile."
          }
        end
        next
      end

      {
        "relationship_type" => "member_of",
        "source_id" => municipality.fetch("canonical_id"),
        "target_id" => by_civicinfo_id.fetch(regional_id).fetch("canonical_id"),
        "source_url" => source_url,
        "source_publisher" => "CivicInfo BC",
        "retrieved_at" => @retrieved_at.iso8601,
        "notes" => "The CivicInfo municipality profile links directly to the regional-district directory record. Evidence: #{source_url}"
      }
    rescue StandardError => error
      @mutex.synchronize do
        gaps << { "canonical_id" => municipality.fetch("canonical_id"), "reason" => "Profile fetch failed: #{error.message}" }
      end
      nil
    end.compact
    [ relationships.sort_by { |row| row.fetch("source_id") }, gaps.sort_by { |row| row.fetch("canonical_id") } ]
  end

  def membership_profile_bodies(civic_id)
    urls = [
      "https://r.jina.ai/http://www.civicinfo.bc.ca/municipalities?id=#{civic_id}&refresh=#{date_token}",
      "https://r.jina.ai/http://civicinfo.bc.ca/municipalities?id=#{civic_id}&refresh=#{date_token}&detail=1"
    ]
    bodies = []
    urls.each_with_index do |url, index|
      body = fetch(url)
      bodies << body
      @raw_dir.join("civicinfo-profiles", "municipality-#{civic_id}-#{index + 1}.md").tap do |path|
        @mutex.synchronize { FileUtils.mkdir_p(path.dirname); path.binwrite(body) }
      end
      break if body.match?(/regionaldistricts\?id=\d+/i)
    rescue StandardError
      next
    end
    bodies
  end

  def scrape_reports(row)
    website = normalize_website(row.fetch("website_url"))
    pages, candidates, searched, discovery_errors = discover_reports(website)
    pages.first(@max_pages).each do |page_url|
      begin
        body = fetch_with_jina_fallback(page_url)
        candidates.concat(extract_report_links(body, page_url))
      rescue StandardError => error
        discovery_errors << "#{page_url}: #{error.message}"
      end
    end
    candidates.uniq! { |candidate| normalized_url(candidate.fetch(:url)) }
    discovered_candidate_count = candidates.length
    candidates = candidates.first(@max_documents)

    download_errors = []
    reports = candidates.filter_map do |candidate|
      classify_and_archive(row, candidate)
    rescue StandardError => error
      download_errors << "#{candidate.fetch(:url)}: #{error.message}"
      nil
    end
    reports.uniq! { |report| [ report.fetch("document_type"), report.fetch("download_url") ] }

    gaps = []
    gaps << "No audited financial statement, annual report, or SOFI asset was verified from the official site." if reports.empty?
    gaps << "Discovery found #{discovered_candidate_count} candidate assets; this shallow run validated the configured cap of #{@max_documents}." if discovered_candidate_count > @max_documents
    gaps << "#{download_errors.length} candidate report assets failed validation or download." if download_errors.any?
    gaps << "Discovery encountered #{discovery_errors.length} page or sitemap failures." if discovery_errors.any?
    {
      "canonical_id" => row.fetch("canonical_id"),
      "searched_locations" => searched.uniq.sort,
      "gaps" => gaps,
      "financial_statements" => reports.select { |report| report["document_type"] == "financial-statements" },
      "annual_reports" => reports.select { |report| report["document_type"] == "annual-report" },
      "sofi_documents" => reports.select { |report| report["document_type"] == "statement-of-financial-information" }
    }
  end

  def discover_reports(website)
    root_uri = URI(website)
    root_uri.path = "/"
    root_uri.query = nil
    root_uri.fragment = nil
    root = root_uri.to_s
    searched = [ root ]
    errors = []
    sitemap_urls = Set.new
    begin
      robots_url = URI.join(root, "/robots.txt").to_s
      robots = fetch(robots_url)
      searched << robots_url
      robots.scan(/^Sitemap:\s*(\S+)/i) { |match| sitemap_urls << match.first }
    rescue StandardError => error
      errors << error.message
    end
    %w[/sitemap.xml /sitemap_index.xml /wp-sitemap.xml].each { |path| sitemap_urls << URI.join(root, path).to_s }

    all_urls = Set.new
    sitemap_urls.to_a.first(10).each do |url|
      collect_sitemap_urls(url, all_urls, searched, errors, depth: 0)
    end

    pages = []
    candidates = []
    all_urls.each do |url|
      evidence = CGI.unescape(url)
      next unless evidence.match?(REPORT_PATTERN)
      next if evidence.match?(EXCLUDE_PATTERN)
      if likely_pdf_url?(url)
        candidates << { url: url, label: File.basename(URI(url).path), source_page_url: url }
      else
        pages << url
      end
    rescue URI::InvalidURIError
      next
    end

    ([ root ] + COMMON_REPORT_PATHS.map { |path| URI.join(root, path).to_s }).each do |page_url|
      begin
        body = fetch_with_jina_fallback(page_url)
        searched << page_url
        links = extract_report_links(body, page_url)
        candidates.concat(links.select { |link| likely_pdf_url?(link.fetch(:url)) })
        pages.concat(links.reject { |link| likely_pdf_url?(link.fetch(:url)) }.map { |link| link.fetch(:url) })
      rescue StandardError
        next
      end
    end
    [ pages.uniq, candidates, searched, errors ]
  end

  def collect_sitemap_urls(url, collected, searched, errors, depth:)
    return if depth > 2 || searched.include?(url)
    body = fetch(url, max_bytes: 50 * 1024 * 1024)
    searched << url
    locations = body.scan(SITEMAP_LOC_PATTERN).flatten.map { |value| CGI.unescapeHTML(value.strip) }.reject(&:empty?)
    if body.match?(/<sitemapindex/i)
      locations.first(40).each { |child| collect_sitemap_urls(child, collected, searched, errors, depth: depth + 1) }
    else
      locations.first(75_000).each { |location| collected << location }
    end
  rescue StandardError => error
    errors << "#{url}: #{error.message}"
  end

  def extract_report_links(body, base_url)
    links = []
    body.scan(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/).each do |label, href|
      append_report_link(links, label, href, base_url)
    end
    body.scan(/<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/im).each do |href, raw_label|
      append_report_link(links, raw_label.gsub(/<[^>]+>/, " "), href, base_url)
    end
    links
  end

  def append_report_link(links, label, href, base_url)
    evidence = "#{CGI.unescapeHTML(label)} #{CGI.unescape(href)}"
    return unless evidence.match?(REPORT_PATTERN)
    return if evidence.match?(EXCLUDE_PATTERN)
    absolute = URI.join(base_url, CGI.unescapeHTML(href)).to_s
    return unless absolute.match?(/\Ahttps?:\/\//)
    links << { url: absolute, label: CGI.unescapeHTML(label).strip, source_page_url: base_url }
  rescue URI::InvalidURIError
    nil
  end

  def classify_and_archive(row, candidate)
    label = candidate.fetch(:label).to_s
    url = candidate.fetch(:url)
    evidence = CGI.unescape("#{label} #{url}")
    return if evidence.match?(EXCLUDE_PATTERN)
    type = if evidence.match?(/(?:\bsofi\b|statement[\s_-]+of[\s_-]+financial[\s_-]+information)/i)
      "statement-of-financial-information"
    elsif evidence.match?(/annual[\s_-]+(?:municipal[\s_-]+)?report/i)
      "annual-report"
    elsif evidence.match?(/(?:audited[^\n]{0,50}financial|financial[\s_-]+statements?)/i)
      "financial-statements"
    end
    return unless type
    year = report_year(evidence)
    return unless year

    asset = archive_pdf(url)
    title_type = { "statement-of-financial-information" => "Statement of Financial Information", "annual-report" => "Annual Report", "financial-statements" => "Audited Financial Statements" }.fetch(type)
    asset.merge(
      "canonical_id" => row.fetch("canonical_id"),
      "title" => label.empty? ? "#{row.fetch('official_name')} #{title_type} — #{year}" : label,
      "document_type" => type,
      "document_variant" => "general",
      "fiscal_period_start" => "#{year}-01-01",
      "fiscal_period_end" => "#{year}-12-31",
      "published_on" => nil,
      "source_page_url" => candidate.fetch(:source_page_url),
      "download_url" => url,
      "languages" => [ "en" ],
      "retrieved_at" => @retrieved_at.iso8601,
      "rights_status" => "metadata_only",
      "notes" => "Official regional government website."
    )
  end

  def report_year(evidence)
    years = evidence.scan(/(?<!\d)(20\d{2})(?!\d)/).flatten.map(&:to_i)
    years.reverse.find { |year| year.between?(2000, @retrieved_at.year) }
  end

  def archive_pdf(url)
    bytes = fetch(url, max_bytes: 125 * 1024 * 1024)
    raise "response is not a PDF" unless bytes.start_with?("%PDF-")
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

  def build_release(previous, base, batch, relationships, normalized_path, batch_path, relationships_path)
    release = previous.reject { |key, _value| %w[municipalities raw_input_files scrape_audit].include?(key) }
    update_release_metadata!(release)
    reports_by_id = batch.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    prior_by_id = previous.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    release["municipalities"] = base.fetch("municipalities").map do |row|
      prior = prior_by_id[row.fetch("canonical_id")]
      documents = if prior
        Array(prior["documents"])
      else
        release_documents(reports_by_id.fetch(row.fetch("canonical_id")))
      end
      row.reject { |key, _value| %w[financial_statements annual_reports sofi_documents].include?(key) }.merge("documents" => documents)
    end
    release["relationships"] = relationships
    release["coverage"] = coverage_rows(release.fetch("municipalities"), relationships)
    release["raw_input_files"] = [ normalized_path, batch_path, relationships_path ].map { |path| file_record(path) }
    release["scrape_audit"] = {
      "batches" => [ file_record(batch_path).merge("batch" => batch.fetch("batch"), "retrieved_at" => batch.fetch("retrieved_at")) ],
      "institutions" => batch.fetch("municipalities").to_h do |row|
        [ row.fetch("canonical_id"), [ {
          "batch" => batch_path.basename.to_s,
          "searched_locations" => Array(row["searched_locations"]),
          "gaps" => Array(row["gaps"])
        } ] ]
      end
    }
    release
  end

  def release_documents(report_row)
    reports = %w[financial_statements annual_reports sofi_documents].flat_map { |key| Array(report_row[key]) }
    reports.group_by do |report|
      year = report.fetch("fiscal_period_end")[0, 4]
      "#{report.fetch('canonical_id')}/documents/#{report.fetch('document_type')}/#{year}/#{report.fetch('document_variant', 'general')}"
    end.map do |canonical_id, matches|
      primary = matches.first
      {
        "canonical_id" => canonical_id,
        "document_type" => primary.fetch("document_type"),
        "document_variant" => primary.fetch("document_variant", "general"),
        "title" => primary.fetch("title"),
        "fiscal_period_start" => primary.fetch("fiscal_period_start"),
        "fiscal_period_end" => primary.fetch("fiscal_period_end"),
        "source_page_url" => primary.fetch("source_page_url"),
        "download_url" => primary.fetch("download_url"),
        "notes" => primary["notes"],
        "assets" => matches.map.with_index do |report, index|
          {
            "content_sha256" => report.fetch("content_sha256"),
            "asset_role" => "final",
            "preferred" => index.zero?,
            "download_url" => report.fetch("download_url"),
            "retrieved_at" => report.fetch("retrieved_at"),
            "archive_path" => report.fetch("archive_path"),
            "mime_type" => report.fetch("mime_type"),
            "byte_size" => report.fetch("byte_size"),
            "rights_status" => report.fetch("rights_status")
          }
        end
      }.compact
    end.sort_by { |document| document.fetch("canonical_id") }
  end

  def update_base_metadata!(base)
    base["release_version"] = RELEASE_DATE
    base["effective_on"] = RELEASE_DATE
    base["source_retrieved_at"] = @retrieved_at.iso8601
    base["roster_source_url"] = CIVICINFO_DIRECTORIES
    base["roster_source_urls"] = [ "https://www.civicinfo.bc.ca/municipalities", CIVICINFO_ROSTER ]
    base["roster_source_title"] = "British Columbia Municipalities and Regional Districts & Islands Trust directories"
  end

  def update_release_metadata!(release)
    release["release_version"] = RELEASE_DATE
    release["effective_on"] = RELEASE_DATE
    release["published_at"] = RELEASE_PUBLISHED_AT
    release["source_retrieved_at"] = @retrieved_at.iso8601
    release["roster_source_url"] = CIVICINFO_DIRECTORIES
    release["roster_source_urls"] = [ "https://www.civicinfo.bc.ca/municipalities", CIVICINFO_ROSTER ]
    release["roster_source_title"] = "British Columbia Municipalities and Regional Districts & Islands Trust directories"
  end

  def relationships_payload(relationships, gaps)
    {
      "release_version" => RELEASE_DATE,
      "retrieved_at" => @retrieved_at.iso8601,
      "relationship_type" => "member_of",
      "relationship_count" => relationships.length,
      "evidence_gaps" => gaps
    }
  end

  def report_summary(rows)
    financial = rows.sum { |row| Array(row["financial_statements"]).length }
    annual = rows.sum { |row| Array(row["annual_reports"]).length }
    sofi = rows.sum { |row| Array(row["sofi_documents"]).length }
    {
      "financial_statement_assets" => financial,
      "annual_report_assets" => annual,
      "sofi_assets" => sofi,
      "institutions_with_reports" => rows.count { |row| %w[financial_statements annual_reports sofi_documents].any? { |key| Array(row[key]).any? } },
      "institutions_with_gaps" => rows.count { |row| Array(row["gaps"]).any? },
      "institutions" => rows.length
    }
  end

  def coverage_rows(institutions, relationships)
    institution_count = institutions.length
    website_count = institutions.count { |row| !row["website_url"].to_s.empty? }
    geography_count = institutions.count { |row| Array(row["statcan_geographies"]).any? }
    geography_gaps = institutions.reject { |row| Array(row["statcan_geographies"]).any? }.map { |row| row.fetch("official_name") }
    documents = institutions.flat_map { |row| Array(row["documents"]) }
    report_counts = {
      "financial-statements" => [ "financial-statements", "audited financial statement" ],
      "annual-reports" => [ "annual-report", "annual report" ],
      "statement-of-financial-information" => [ "statement-of-financial-information", "statement of financial information" ]
    }.transform_values do |document_type, label|
      matching = documents.select { |document| document["document_type"] == document_type }
      institution_total = institutions.count do |institution|
        Array(institution["documents"]).any? { |document| document["document_type"] == document_type }
      end
      [ institution_total, matching.length, matching.sum { |document| Array(document["assets"]).length }, label ]
    end
    assets = documents.flat_map { |document| Array(document["assets"]) }
    missing_assets = assets.count do |asset|
      path = asset["archive_path"]
      path.to_s.empty? || !@asset_root.join(path).file?
    end

    rows = [
      coverage_row("institutions", "complete", "#{institution_count} institutions emitted from the complete CivicInfo municipality and Regional Districts & Islands Trust directory scopes.", CIVICINFO_DIRECTORIES),
      coverage_row("websites", website_count == institution_count ? "complete" : "partial", "#{website_count} of #{institution_count} institutions have an upstream-verified official website URL.", CIVICINFO_DIRECTORIES),
      coverage_row("geographies", geography_count == institution_count ? "complete" : (geography_count.zero? ? "not-found" : "partial"), "#{geography_count} of #{institution_count} institutions have a Statistics Canada SGC 2021 jurisdiction geography association. No association was emitted for: #{geography_gaps.join(', ')}.", STATCAN_SOURCE),
      coverage_row("relationships", relationships.empty? ? "not-found" : "partial", "#{relationships.length} explicit municipality-to-regional-district member_of relationships were emitted from provincial voting-strength schedules or CivicInfo profiles; non-municipal and unresolved membership was not inferred.", BC_VOTING_STRENGTH_SOURCE)
    ]
    report_counts.each do |subject, (institution_total, work_total, asset_total, label)|
      status = work_total.zero? ? "not-found" : (institution_total == institution_count ? "complete" : "partial")
      rows << coverage_row(subject, status, "#{work_total} emitted #{label} document works comprise #{asset_total} archived PDF assets for #{institution_total} of #{institution_count} institutions after official-site searches.")
    end
    asset_status = assets.empty? ? "not-found" : (missing_assets.zero? ? "complete" : "partial")
    rows << coverage_row("document-assets", asset_status, "#{assets.length - missing_assets} of #{assets.length} emitted document assets resolve to SHA-256 archived PDF files; #{missing_assets} are missing.")
    rows
  end

  def coverage_row(subject, status, notes, source_url = nil)
    { "scope_id" => "ca/bc", "subject" => subject, "status" => status, "notes" => notes }.tap do |row|
      row["source_url"] = source_url if source_url
    end
  end

  def release_document_summary(institutions)
    documents = institutions.flat_map { |row| Array(row["documents"]) }
    counts = {
      "financial-statements" => "financial_statement",
      "annual-report" => "annual_report",
      "statement-of-financial-information" => "statement_of_financial_information"
    }.each_with_object({}) do |(document_type, prefix), result|
      matching = documents.select { |document| document["document_type"] == document_type }
      result["#{prefix}_documents"] = matching.length
      result["#{prefix}_assets"] = matching.sum { |document| Array(document["assets"]).length }
    end
    counts.merge(
      "document_works" => documents.length,
      "document_assets" => documents.sum { |document| Array(document["assets"]).length },
      "institutions_with_reports" => institutions.count { |row| Array(row["documents"]).any? }
    )
  end

  def build_summary(base, batch, relationships, membership_gaps, regional_reports)
    regional_assets = report_summary(regional_reports)
    report_summary(batch.fetch("municipalities")).merge(
      "release_version" => RELEASE_DATE,
      "retrieved_at" => @retrieved_at.iso8601,
      "municipalities" => base.fetch("municipalities").count { |row| %w[municipality government_district].include?(row["jurisdiction_kind"]) },
      "regional_districts" => base.fetch("municipalities").count { |row| row["jurisdiction_kind"] == "regional_district" },
      "islands_trust" => base.fetch("municipalities").count { |row| row["jurisdiction_kind"] == "islands_trust" },
      "regional_directory_records" => regional_reports.length,
      "regional_financial_statement_assets" => regional_assets.fetch("financial_statement_assets"),
      "regional_annual_report_assets" => regional_assets.fetch("annual_report_assets"),
      "regional_sofi_assets" => regional_assets.fetch("sofi_assets"),
      "regional_institutions_with_reports" => regional_assets.fetch("institutions_with_reports"),
      "regional_institutions_with_gaps" => regional_assets.fetch("institutions_with_gaps"),
      "member_of_relationships" => relationships.length,
      "membership_evidence_gaps" => membership_gaps.length,
      "statcan_geography_associations" => base.fetch("municipalities").sum { |row| Array(row["statcan_geographies"]).length },
      "institution_level_statcan_identifiers" => base.fetch("municipalities").sum { |row| Array(row["identifiers"]).count { |identifier| identifier.fetch("scheme", "").start_with?("statcan.") } },
      "shishalh_canonical_id" => SHISHALH_NEW_ID,
      "output_dir" => @output_dir.to_s,
      "asset_root" => @asset_root.to_s
    )
  end

  def copy_statcan_source
    destination = @raw_dir.join(@statcan_csv.basename)
    FileUtils.cp(@statcan_csv, destination) unless destination.exist?
  end

  def source_record(url, publisher, title)
    {
      "url" => url,
      "publisher_name" => publisher,
      "title" => title,
      "retrieved_at" => @retrieved_at.iso8601,
      "languages" => [ "en" ],
      "license" => nil,
      "attribution" => nil
    }
  end

  def civicinfo_id(row)
    Array(row.fetch("identifiers")).find { |identifier| identifier["scheme"] == "civicinfo.bc.organization" }.fetch("value")
  end

  def normalize_name(value)
    value.to_s.dup.force_encoding(Encoding::UTF_8).scrub.gsub(/&nbsp;|&#160;/i, " ").unicode_normalize(:nfkd)
      .encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def slugify(value)
    normalize_name(value).tr(" ", "-")
  end

  def normalize_website(value)
    value.match?(/\Ahttps?:\/\//) ? value : "https://#{value}"
  end

  def normalized_url(value)
    uri = URI(value)
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    value
  end

  def likely_pdf_url?(url)
    uri = URI(url)
    uri.path.downcase.end_with?(".pdf") || uri.query.to_s.match?(/(?:pdf|download|document)/i)
  rescue URI::InvalidURIError
    false
  end

  def fetch_with_jina_fallback(url)
    fetch(url)
  rescue StandardError
    uri = URI(url)
    fetch("https://r.jina.ai/http://#{uri.host}#{uri.request_uri}")
  end

  def fetch(url, redirects: 8, max_bytes: 20 * 1024 * 1024)
    raise "too many redirects for #{url}" if redirects.negative?
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "*/*"
    response = request_with_retries(uri, request)
    case response
    when Net::HTTPSuccess
      body = response.body
      raise "response exceeds #{max_bytes} bytes" if body.bytesize > max_bytes
      body
    when Net::HTTPRedirection
      fetch(URI.join(url, response.fetch("location")).to_s, redirects: redirects - 1, max_bytes: max_bytes)
    else
      raise "HTTP #{response.code} for #{url}"
    end
  end

  def request_with_retries(uri, request)
    attempts = 0
    begin
      attempts += 1
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 8, read_timeout: 12) do |http|
        http.request(request)
      end
    rescue IOError, EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
      retry if attempts < 2
      raise
    end
  end

  def parallel_map(items)
    queue = Queue.new
    items.each_with_index { |item, index| queue << [ index, item ] }
    results = Array.new(items.length)
    workers = [ @threads, items.length ].min.times.map do
      Thread.new do
        loop do
          index, item = queue.pop(true)
          results[index] = yield(item)
        rescue ThreadError
          break
        end
      end
    end
    workers.each(&:join)
    results
  end

  def file_record(path)
    { "name" => path.basename.to_s, "sha256" => Digest::SHA256.file(path).hexdigest, "byte_size" => path.size }
  end

  def report_checkpoint_path(row)
    @raw_dir.join("report-checkpoints", "#{slugify(row.fetch('canonical_id'))}.json")
  end

  def read_json(path)
    JSON.parse(path.read)
  end

  def write_json(path, object)
    FileUtils.mkdir_p(path.dirname)
    temporary = Pathname("#{path}.tmp")
    temporary.write(JSON.pretty_generate(object) + "\n")
    FileUtils.mv(temporary, path)
  end

  def date_token
    @retrieved_at.to_date.strftime("%Y%m%d")
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    base_dir: "/Volumes/floppy/york_factory/public_institutions/sources/bc-municipalities/2026-08-20",
    output_dir: "/Volumes/floppy/york_factory/public_institutions/sources/bc-municipalities/2026-08-21",
    asset_root: "/Volumes/floppy/york_factory/public_institutions/assets",
    statcan_csv: "/Volumes/floppy/york_factory/public_institutions/sources/ns-municipalities/2026-08-20/sgc-cgt-2021-structure-eng.csv",
    threads: 8,
    max_pages: 60,
    max_documents: 160
  }

  OptionParser.new do |parser|
    parser.banner = "Usage: bundle exec ruby script/augment_bc_regional_districts.rb [options]"
    parser.on("--base-dir PATH") { |value| options[:base_dir] = value }
    parser.on("--output-dir PATH") { |value| options[:output_dir] = value }
    parser.on("--asset-root PATH") { |value| options[:asset_root] = value }
    parser.on("--statcan-csv PATH") { |value| options[:statcan_csv] = value }
    parser.on("--threads NUMBER", Integer) { |value| options[:threads] = value }
    parser.on("--max-pages NUMBER", Integer) { |value| options[:max_pages] = value }
    parser.on("--max-documents NUMBER", Integer) { |value| options[:max_documents] = value }
  end.parse!

  summary = BcRegionalDistrictAugmenter.new(**options).run
  puts JSON.pretty_generate(summary)
end
