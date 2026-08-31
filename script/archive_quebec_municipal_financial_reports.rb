#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "optparse"
require "pathname"
require "set"
require "thread"
require "time"
require "uri"

class ArchiveQuebecMunicipalFinancialReports
  USER_AGENT = "YorkFactory public-government-data crawler; contact data@buildcanada.com"
  DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  IDENTIFIER_SCHEMES = [ "qc.code-geographique", "qc.repertoire.mrc_cm_ar_code" ].freeze
  INDEX_SOURCE_URL = "https://www.mamh.gouv.qc.ca/documentsfinanciersweb/rapportfinancier.json"

  def initialize(manifest_path:, index_path:, output_path:, retrieved_at:, asset_root: DEFAULT_ASSET_ROOT,
    threads: 8, years: nil)
    @manifest_path = Pathname(manifest_path).expand_path
    @index_path = Pathname(index_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @asset_root = Pathname(asset_root).expand_path
    @threads = Integer(threads)
    @years = years&.map { Integer(_1) }&.to_set
    @mutex = Mutex.new
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    FileUtils.mkdir_p([ @output_path.dirname, @asset_root.join("sha256") ])
    manifest = JSON.parse(@manifest_path.read)
    index = JSON.parse(@index_path.read)
    institutions_by_code = manifest.fetch("municipalities").filter_map do |row|
      identifier = row.fetch("identifiers", []).find { IDENTIFIER_SCHEMES.include?(_1["scheme"]) }
      [ identifier["value"], row ] if identifier
    end.to_h
    indexed = index.fetch("ListeDesRapports").flat_map do |year_row|
      year = Integer(year_row.fetch("Annee"))
      next [] if @years && !@years.include?(year)

      year_row.fetch("Details").filter_map do |report|
        institution = institutions_by_code[report.fetch("CodeGeographique")]
        build_candidate(institution, report, year) if institution
      end
    end

    results = parallel_map(indexed) { archive_report(_1) }
    successes = results.select { _1["report"] }
    failures = results.reject { _1["report"] }
    grouped = manifest.fetch("municipalities").map do |institution|
      reports = successes.filter_map do |result|
        result["report"] if result.fetch("canonical_id") == institution.fetch("canonical_id")
      end
      errors = failures.filter_map do |result|
        result["error"] if result.fetch("canonical_id") == institution.fetch("canonical_id")
      end
      {
        "canonical_id" => institution.fetch("canonical_id"),
        "official_name" => institution["official_name_fr"] || institution["official_name_en"],
        "website_url" => institution["website_url"],
        "searched_locations" => [ INDEX_SOURCE_URL ],
        "candidate_count" => reports.length + errors.length,
        "validated_report_count" => reports.length,
        "reports" => reports.sort_by { [ _1.fetch("year"), _1.fetch("download_url") ] },
        "gaps" => errors.empty? ? [] : [ "#{errors.length} indexed reports failed download or PDF validation." ],
        "discovery_errors" => [],
        "candidate_errors" => errors,
        "review_rejections" => []
      }
    end
    payload = {
      "batch" => "qc-central-municipal-financial-reports",
      "source_manifest" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "source_index" => @index_path.to_s,
      "source_index_url" => INDEX_SOURCE_URL,
      "source_index_sha256" => Digest::SHA256.file(@index_path).hexdigest,
      "source_index_updated_at" => index["DateHeureMAJ"],
      "retrieved_at" => @retrieved_at.iso8601,
      "institution_count" => grouped.length,
      "institutions_with_reports" => grouped.count { _1["reports"].any? },
      "validated_report_count" => successes.length,
      "financial_statement_count" => successes.length,
      "annual_report_count" => 0,
      "sofi_count" => 0,
      "institutions" => grouped,
      "failures" => failures
    }
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    puts JSON.pretty_generate(payload.slice("institution_count", "institutions_with_reports", "validated_report_count").merge(
      "failed_report_count" => failures.length,
      "output" => @output_path.to_s,
      "sha256" => Digest::SHA256.file(@output_path).hexdigest
    ))
  end

  private

  def build_candidate(institution, report, year)
    return if report["Lien"].to_s.empty?

    {
      "canonical_id" => institution.fetch("canonical_id"),
      "official_name" => institution["official_name_fr"] || institution["official_name_en"],
      "year" => year,
      "title" => report.fetch("Titre"),
      "url" => report.fetch("Lien"),
      "expected_size" => Integer(report["TailleFichier"], exception: false)
    }
  end

  def archive_report(candidate)
    bytes, resolved_url = fetch(candidate.fetch("url"))
    raise "response is not a PDF" unless bytes.start_with?("%PDF-")
    expected = candidate["expected_size"]
    if expected
      difference = (expected - bytes.bytesize).abs
      tolerance = [ (expected * 0.01).ceil, 4_096 ].max
      raise "size outside tolerance: reported #{expected}, got #{bytes.bytesize}" if difference > tolerance
    end

    sha256 = Digest::SHA256.hexdigest(bytes)
    relative = Pathname("sha256").join(sha256[0, 2], "#{sha256}.pdf")
    destination = @asset_root.join(relative)
    @mutex.synchronize do
      FileUtils.mkdir_p(destination.dirname)
      destination.binwrite(bytes) unless destination.exist?
    end
    {
      "canonical_id" => candidate.fetch("canonical_id"),
      "report" => {
        "content_sha256" => sha256,
        "byte_size" => bytes.bytesize,
        "mime_type" => "application/pdf",
        "archive_path" => relative.to_s,
        "document_type" => "financial-statements",
        "year" => candidate.fetch("year"),
        "title" => candidate.fetch("title"),
        "source_page_url" => "https://www.quebec.ca/gouvernement/gestion-municipale/finances-fiscalite-municipales/information-financiere/publications-financieres/rapport-financier",
        "download_url" => resolved_url,
        "languages" => [ "fr" ],
        "retrieved_at" => @retrieved_at.iso8601,
        "rights_status" => "metadata_only",
        "verification" => {
          "listed_by_provincial_authority" => true,
          "geographic_code_matched" => true,
          "source_reported_byte_size" => expected,
          "source_reported_size_within_tolerance" => expected ? true : nil,
          "pdf_signature_valid" => true
        }
      }
    }
  rescue StandardError => error
    {
      "canonical_id" => candidate.fetch("canonical_id"),
      "url" => candidate.fetch("url"),
      "year" => candidate.fetch("year"),
      "error" => "#{candidate.fetch('url')}: #{error.class}: #{error.message}"
    }
  end

  def fetch(url, redirects: 6)
    raise "too many redirects" if redirects.zero?

    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "application/pdf"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 20, read_timeout: 120) do |http|
      http.request(request)
    end
    if response.is_a?(Net::HTTPRedirection)
      location = response["location"]
      raise "redirect without location" if location.to_s.empty?

      return fetch(URI.join(uri, location).to_s, redirects: redirects - 1)
    end
    raise "HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

    [ response.body, uri.to_s ]
  end

  def parallel_map(rows)
    queue = Queue.new
    rows.each_with_index { |row, index| queue << [ index, row ] }
    results = Array.new(rows.length)
    workers = Array.new(@threads) do
      Thread.new do
        loop do
          index, row = queue.pop(true)
          results[index] = yield(row)
        rescue ThreadError
          break
        end
      end
    end
    workers.each(&:join)
    results
  end
end

options = { threads: 8 }
OptionParser.new do |parser|
  parser.banner = "Usage: archive_quebec_municipal_financial_reports.rb --manifest PATH --index PATH --output PATH --retrieved-at ISO8601"
  parser.on("--manifest PATH") { options[:manifest_path] = _1 }
  parser.on("--index PATH") { options[:index_path] = _1 }
  parser.on("--output PATH") { options[:output_path] = _1 }
  parser.on("--retrieved-at TIME") { options[:retrieved_at] = _1 }
  parser.on("--asset-root PATH") { options[:asset_root] = Pathname(_1) }
  parser.on("--threads N", Integer) { options[:threads] = _1 }
  parser.on("--years YEARS", "Comma-separated years; omit for all indexed years") do
    options[:years] = _1.split(",").map(&:strip).reject(&:empty?)
  end
end.parse!

missing = %i[manifest_path index_path output_path retrieved_at].reject { options[_1] }
abort "missing options: #{missing.join(', ')}" if missing.any?

ArchiveQuebecMunicipalFinancialReports.new(**options).run
