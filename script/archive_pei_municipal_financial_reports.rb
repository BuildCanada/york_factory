#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "json"
require "optparse"
require "pathname"
require "thread"
require "time"
require "uri"
require_relative "scrape_municipal_financial_reports"

class ArchivePeiMunicipalFinancialReports
  SOURCE_URL = "https://www.princeedwardisland.ca/en/feature/municipal-financial-document-search"
  NAME_ALIASES = {
    "annandale little pond howebay" => "ca/pe/annandale-little-pond-howe-bay",
    "cenrtral kings" => "ca/pe/central-kings",
    "cl" => "ca/pe/clyde-river",
    "malpeque" => "ca/pe/malpeque-bay",
    "resort" => "ca/pe/resort",
    "resort municipality" => "ca/pe/resort",
    "st louis" => "ca/pe/st-louis",
    "st peters" => "ca/pe/st-peter-s-bay",
    "st peters bay" => "ca/pe/st-peter-s-bay"
  }.freeze

  def initialize(manifest_path:, index_glob:, output_path:, retrieved_at:, threads: 6,
    download_dir: nil, common_crawl_fallback: false, common_crawl_collections: 12,
    common_crawl_index_urls: nil, common_crawl_only: false, wayback_fallback: false,
    wayback_only: false,
    asset_root: MunicipalFinancialReportScraper::DEFAULT_ASSET_ROOT)
    @manifest_path = Pathname(manifest_path).expand_path
    @index_glob = index_glob
    @output_path = Pathname(output_path).expand_path
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @threads = Integer(threads)
    @download_dir = Pathname(download_dir).expand_path if download_dir
    @common_crawl_fallback = common_crawl_fallback
    @common_crawl_index_urls = common_crawl_index_urls
    @common_crawl_only = common_crawl_only
    @wayback_fallback = wayback_fallback
    @wayback_only = wayback_only
    @common_crawl_discovery_errors = []
    @wayback_discovery_errors = []
    @scraper = MunicipalFinancialReportScraper.new(
      manifest_path: @manifest_path,
      output_dir: @output_path.dirname,
      retrieved_at: @retrieved_at.iso8601,
      common_crawl_collections: common_crawl_collections,
      asset_root: asset_root
    )
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    municipalities = manifest.fetch("municipalities")
    by_id = municipalities.to_h { [ _1.fetch("canonical_id"), _1 ] }
    by_name = municipalities.to_h { [ normalize_name(official_name(_1)), _1.fetch("canonical_id") ] }
    index_paths = Dir.glob(@index_glob).map { Pathname(_1).expand_path }.sort
    raise "no index files matched #{@index_glob}" if index_paths.empty?

    index_rows = index_paths.flat_map do |path|
      payload = JSON.parse(path.read)
      payload.fetch("rows").filter_map do |row|
        next unless row["document_type"] == "Financial Statements"

        row.merge("index_path" => path.to_s)
      end
    end
    matched, unmatched = index_rows.partition do |row|
      canonical_id = canonical_id_for(row.fetch("municipality"), by_name)
      canonical_id && by_id.key?(canonical_id)
    end
    if @common_crawl_fallback
      @common_crawl_candidates_by_object_id = common_crawl_candidates(index_rows)
      puts JSON.generate(
        common_crawl_object_ids: @common_crawl_candidates_by_object_id.length,
        common_crawl_captures: @common_crawl_candidates_by_object_id.values.sum(&:length),
        common_crawl_discovery_errors: @common_crawl_discovery_errors.length
      )
    end
    if @wayback_fallback
      @wayback_candidates_by_object_id = wayback_candidates(index_rows)
      puts JSON.generate(
        wayback_object_ids: @wayback_candidates_by_object_id.length,
        wayback_captures: @wayback_candidates_by_object_id.values.sum(&:length),
        wayback_discovery_errors: @wayback_discovery_errors.length
      )
    end
    work = matched.group_by { canonical_id_for(_1.fetch("municipality"), by_name) }

    results = parallel_map(work.to_a) do |canonical_id, rows|
      archive_institution(by_id.fetch(canonical_id), rows)
    end
    reports = results.flat_map { _1.fetch("reports") }
    payload = {
      "batch" => "pe-municipal-financial-reports-provincial-index",
      "source_manifest" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "source_url" => SOURCE_URL,
      "source_indexes" => index_paths.map do |path|
        {
          "path" => path.to_s,
          "sha256" => Digest::SHA256.file(path).hexdigest,
          "result_count" => JSON.parse(path.read).fetch("result_count")
        }
      end,
      "retrieved_at" => @retrieved_at.iso8601,
      "common_crawl_fallback" => @common_crawl_fallback,
      "common_crawl_discovery_errors" => @common_crawl_discovery_errors,
      "wayback_fallback" => @wayback_fallback,
      "wayback_discovery_errors" => @wayback_discovery_errors,
      "institution_count" => results.length,
      "institutions_with_reports" => results.count { _1.fetch("reports").any? },
      "validated_report_count" => reports.length,
      "financial_statement_count" => reports.count { _1["document_type"] == "financial-statements" },
      "annual_report_count" => reports.count { _1["document_type"] == "annual-report" },
      "sofi_count" => reports.count { _1["document_type"] == "statement-of-financial-information" },
      "unmatched_index_records" => unmatched,
      "institutions" => results.sort_by { _1.fetch("canonical_id") }
    }
    @output_path.dirname.mkpath
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    puts JSON.pretty_generate(payload.slice(
      "institution_count", "institutions_with_reports", "validated_report_count",
      "financial_statement_count", "unmatched_index_records"
    ).merge("output" => @output_path.to_s, "sha256" => Digest::SHA256.file(@output_path).hexdigest))
  end

  private

  def archive_institution(row, index_rows)
    errors = []
    reports = index_rows.flat_map do |index_row|
      validated = []
      candidate_variants(index_row).each do |candidate|
        matching_row = row.merge("official_name_en" => index_row.fetch("municipality"))
        verified = @scraper.send(:verify_and_archive, matching_row, candidate)
        verified.each do |report|
          report.fetch("verification").merge!(
            "official_provincial_index" => true,
            "source_index_municipality" => index_row.fetch("municipality"),
            "source_index_year" => index_row.fetch("year"),
            "source_index_path" => index_row.fetch("index_path")
          )
        end
        unless verified.empty?
          validated = verified
          break
        end
      rescue StandardError => error
        errors << "#{candidate.fetch('url')}: #{error.class}: #{error.message}"
      end
      validated
    end
    reports.uniq! { [ _1.fetch("document_type"), _1.fetch("year"), _1.fetch("content_sha256") ] }
    reports.sort_by! { [ _1.fetch("year"), _1.fetch("download_url") ] }
    {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => official_name(row),
      "website_url" => row["website_url"],
      "searched_locations" => [ SOURCE_URL ],
      "candidate_count" => index_rows.sum { candidate_variants(_1).length },
      "validated_report_count" => reports.length,
      "reports" => reports,
      "gaps" => reports.empty? ? [ "No indexed candidate passed strict content validation." ] : [],
      "discovery_errors" => [],
      "candidate_errors" => errors,
      "review_rejections" => []
    }
  end

  def candidate_variants(index_row)
    direct = candidate_for(index_row)
    object_id = object_id_for(index_row.fetch("url"))
    common_crawl = object_id ? Array(@common_crawl_candidates_by_object_id&.fetch(object_id, nil)) : []
    wayback = object_id ? Array(@wayback_candidates_by_object_id&.fetch(object_id, nil)) : []
    archived = [ *wayback, *common_crawl ]
    variants = if @common_crawl_only || @wayback_only
      archived
    elsif direct["local_path"]
      [ direct, *archived ]
    else
      [ *archived, direct ]
    end
    variants.uniq { [ _1["common_crawl_digest"], _1.fetch("url") ] }
  end

  def wayback_candidates(index_rows)
    known_object_ids = index_rows.filter_map { object_id_for(_1.fetch("url")) }.to_set
    query = URI.encode_www_form(
      url: "wdf.princeedwardisland.ca/download/dms",
      matchType: "prefix",
      output: "json",
      fl: "timestamp,original,statuscode,mimetype,digest",
      filter: [ "statuscode:200", "mimetype:application/pdf" ],
      collapse: "urlkey"
    )
    request_url = "https://web.archive.org/cdx/search/cdx?#{query}"
    rows = JSON.parse(@scraper.send(:fetch_wayback_index, request_url))
    header = rows.shift
    return {} unless header

    candidates = Hash.new { |hash, key| hash[key] = [] }
    rows.each do |values|
      capture = header.zip(values).to_h
      original = capture.fetch("original")
      object_id = object_id_for(original)
      next unless known_object_ids.include?(object_id)

      candidates[object_id] << {
        "url" => "https://web.archive.org/web/#{capture.fetch('timestamp')}id_/#{original}",
        "label" => download_label(original),
        "source_page_url" => SOURCE_URL,
        "original_url" => original,
        "wayback_timestamp" => capture.fetch("timestamp"),
        "wayback_digest" => capture["digest"]
      }
    end
    candidates.transform_values { _1.uniq { |row| row["wayback_digest"] || row.fetch("url") } }
  rescue StandardError => error
    @wayback_discovery_errors << "#{request_url}: #{error.class}: #{error.message}"
    {}
  end

  def common_crawl_candidates(index_rows)
    known_object_ids = index_rows.filter_map { object_id_for(_1.fetch("url")) }.to_set
    candidates = Hash.new { |hash, key| hash[key] = [] }
    index_urls = @common_crawl_index_urls || @scraper.send(:common_crawl_collection_urls)
    index_urls.each do |index_url|
      query = URI.encode_www_form(
        url: "wdf.princeedwardisland.ca/download/dms",
        matchType: "prefix",
        output: "json",
        filter: [ "status:200", "mime:application/pdf" ],
        collapse: "urlkey"
      )
      request_url = "#{index_url}?#{query}"
      body = @scraper.send(:fetch_common_crawl_index, request_url)
      body.each_line do |line|
        next unless line.lstrip.start_with?("{")

        capture = JSON.parse(line)
        object_id = object_id_for(capture.fetch("url"))
        next unless known_object_ids.include?(object_id)

        candidates[object_id] << {
          "url" => capture.fetch("url"),
          "label" => download_label(capture.fetch("url")),
          "source_page_url" => SOURCE_URL,
          "common_crawl_index_url" => request_url,
          "common_crawl_timestamp" => capture["timestamp"],
          "common_crawl_digest" => capture["digest"],
          "common_crawl_filename" => capture.fetch("filename"),
          "common_crawl_offset" => capture.fetch("offset"),
          "common_crawl_length" => capture.fetch("length")
        }
      end
    rescue StandardError => error
      @common_crawl_discovery_errors << "#{index_url}: #{error.class}: #{error.message}"
    end
    candidates.transform_values { _1.uniq { |row| row["common_crawl_digest"] || row.fetch("url") } }
  end

  def object_id_for(url)
    URI(url).then { CGI.parse(_1.query.to_s)["objectId"]&.first }
  rescue URI::InvalidURIError
    nil
  end

  def candidate_for(index_row)
    url = index_row.fetch("url")
    candidate = {
      "url" => url,
      "label" => download_label(url),
      "source_page_url" => SOURCE_URL
    }
    local_path = local_path_for(url)
    candidate["local_path"] = local_path.to_s if local_path
    candidate
  end

  def local_path_for(url)
    return unless @download_dir

    query = URI(url).then { CGI.parse(_1.query.to_s) }
    object_id = query["objectId"]&.first
    file_name = query["fileName"]&.first
    candidates = @download_dir.children.select(&:file?)
    by_object_id = candidates.find { _1.basename.to_s.include?(object_id) } if object_id
    return by_object_id if by_object_id
    return unless file_name

    candidates.find do |candidate|
      downloaded_name = candidate.basename.to_s
      downloaded_name == file_name || downloaded_name.sub(/ \(\d+\)(?=\.[^.]+\z)/, "") == file_name
    end
  rescue URI::InvalidURIError
    nil
  end

  def download_label(url)
    URI(url).then { CGI.parse(_1.query.to_s)["fileName"]&.first }.to_s
  rescue URI::InvalidURIError
    url
  end

  def canonical_id_for(name, by_name)
    normalized = normalize_name(name)
    by_name[normalized] || NAME_ALIASES[normalized]
  end

  def normalize_name(value)
    value.to_s.downcase
      .tr("’", "'")
      .gsub(/\bst[.]?\s*/, "st ")
      .gsub(/[^a-z0-9]+/, " ")
      .strip
  end

  def official_name(row)
    row["official_name_en"] || row["official_name_fr"] || row.fetch("official_name")
  end

  def parallel_map(rows)
    queue = Queue.new
    rows.each_with_index { |row, index| queue << [ index, row ] }
    results = Array.new(rows.length)
    Array.new(@threads) do
      Thread.new do
        loop do
          index, row = queue.pop(true)
          results[index] = yield(*row)
        rescue ThreadError
          break
        end
      end
    end.each(&:join)
    results
  end
end

if $PROGRAM_NAME == __FILE__
  options = { threads: 6, common_crawl_collections: 12 }
  OptionParser.new do |parser|
    parser.banner = "Usage: archive_pei_municipal_financial_reports.rb --manifest PATH --index-glob GLOB --output PATH --retrieved-at ISO8601"
    parser.on("--manifest PATH") { options[:manifest_path] = _1 }
    parser.on("--index-glob GLOB") { options[:index_glob] = _1 }
    parser.on("--output PATH") { options[:output_path] = _1 }
    parser.on("--retrieved-at TIME") { options[:retrieved_at] = _1 }
    parser.on("--threads N", Integer) { options[:threads] = _1 }
    parser.on("--download-dir PATH") { options[:download_dir] = _1 }
    parser.on("--common-crawl-fallback") { options[:common_crawl_fallback] = true }
    parser.on("--common-crawl-only") do
      options[:common_crawl_fallback] = true
      options[:common_crawl_only] = true
    end
    parser.on("--common-crawl-collections N", Integer) { options[:common_crawl_collections] = _1 }
    parser.on("--common-crawl-index-urls URLS", "Comma-separated Common Crawl CDX endpoints") do
      options[:common_crawl_index_urls] = _1.split(",").map(&:strip).reject(&:empty?)
    end
    parser.on("--wayback-fallback") { options[:wayback_fallback] = true }
    parser.on("--wayback-only") do
      options[:wayback_fallback] = true
      options[:wayback_only] = true
    end
    parser.on("--asset-root PATH") { options[:asset_root] = Pathname(_1) }
  end.parse!

  missing = %i[manifest_path index_glob output_path retrieved_at].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  ArchivePeiMunicipalFinancialReports.new(**options).run
end
