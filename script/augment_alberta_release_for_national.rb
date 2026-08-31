#!/usr/bin/env ruby

require "digest"
require "date"
require "fileutils"
require "json"
require "net/http"
require "optparse"
require "pathname"
require "time"
require "uri"

class AlbertaNationalReleaseAugmenter
  CHANGE_SOURCE_URL =
    "https://open.alberta.ca/dataset/7b81986c-b05a-4b72-8f12-aec3a22970ae/resource/" \
      "939a15c5-59a2-44fe-8f65-09f7b7764a99/download/2023-lgcode.pdf"
  STATEMENT_ROOT =
    "https://municipalaffairs.gov.ab.ca/cfml/FinancialTaxRateSearch/pdf/fs"
  METIS_SOURCE_URL = "https://www.alberta.ca/metis-settlements"
  IMPROVEMENT_DISTRICT_CHANGE_SOURCE_URL =
    "https://open.alberta.ca/dataset/7b81986c-b05a-4b72-8f12-aec3a22970ae/resource/" \
      "0ef9bd1b-8e44-401c-b953-9420efc350be/download/2021-lgcode.pdf"
  SPECIAL_AREAS_SOURCE_URL = "https://www.alberta.ca/special-areas-board"

  PREDECESSORS = [
    {
      "canonical_id" => "ca/ab/black-diamond",
      "official_name" => "Town of Black Diamond",
      "municipal_code" => "0030",
      "statcan_uid" => "4806011",
      "statcan_name" => "Black Diamond",
      "filename_name" => "BLACK_DIAMOND"
    },
    {
      "canonical_id" => "ca/ab/turner-valley",
      "official_name" => "Town of Turner Valley",
      "municipal_code" => "0321",
      "statcan_uid" => "4806009",
      "statcan_name" => "Turner Valley",
      "filename_name" => "TURNER_VALLEY"
    }
  ].freeze
  METIS_SETTLEMENTS = {
    "Buffalo Lake" => "0406",
    "East Prairie" => "0407",
    "Elizabeth" => "0408",
    "Fishing Lake" => "0409",
    "Gift Lake" => "0410",
    "Kikino" => "0411",
    "Paddle Prairie" => "0412",
    "Peavine" => "0413"
  }.freeze

  def initialize(input_dir:, output_dir:, release_date:, retrieved_at:, asset_root:)
    @input_dir = Pathname(input_dir)
    @output_dir = Pathname(output_dir)
    @release_date = Date.iso8601(release_date)
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @asset_root = Pathname(asset_root)
  end

  def call
    raise "refusing to overwrite #{@output_dir}" if @output_dir.exist?

    @output_dir.mkpath
    @output_dir.join("raw").mkpath
    @asset_root.join("sha256").mkpath
    base = read_json(@input_dir.join("normalized-municipalities.json"))
    batch = read_json(@input_dir.join("financial-report-batch.json"))
    rename_canonical_ids!(base, batch)
    normalize_current_rows!(base.fetch("municipalities"))
    add_predecessors!(base, batch)
    add_dissolved_improvement_district!(base, batch)
    add_metis_settlements!(base, batch)
    add_relationships!(base)
    freeze_change_source!
    base["release_version"] = @release_date.iso8601
    base["effective_on"] = @release_date.iso8601
    base["provincial_nuance_source_url"] = CHANGE_SOURCE_URL
    batch["retrieved_at"] = @retrieved_at.iso8601
    batch["summary"] = report_summary(batch.fetch("municipalities"))
    write_json(@output_dir.join("normalized-municipalities.json"), base)
    write_json(@output_dir.join("financial-report-batch.json"), batch)
    summary = {
      "province" => "ab",
      "release_version" => @release_date.iso8601,
      "institutions" => base.fetch("municipalities").length,
      "relationships" => base.fetch("relationships").length,
      "documents" => batch.fetch("municipalities").sum do |row|
        Array(row["financial_statements"]).length + Array(row["annual_reports"]).length
      end,
      "predecessor_documents" => batch.fetch("municipalities").select do |row|
        PREDECESSORS.any? { |predecessor| predecessor.fetch("canonical_id") == row.fetch("canonical_id") }
      end.sum { |row| Array(row["financial_statements"]).length }
    }
    write_json(@output_dir.join("scrape-summary.json"), summary)
    summary
  end

  private

  def rename_canonical_ids!(base, batch)
    old_id = "ca/ab/improvement-district"
    new_id = "ca/ab/kananaskis-improvement-district"
    row = base.fetch("municipalities").find { |candidate| candidate.fetch("canonical_id") == old_id }
    raise "Kananaskis Improvement District is missing" unless row

    row["canonical_id"] = new_id
    report_row = batch.fetch("municipalities").find { |candidate| candidate.fetch("canonical_id") == old_id }
    raise "Kananaskis report audit row is missing" unless report_row

    report_row["canonical_id"] = new_id
    %w[financial_statements annual_reports].each do |key|
      Array(report_row[key]).each { |report| report["canonical_id"] = new_id }
    end
  end

  def normalize_current_rows!(rows)
    rows.each do |row|
      row["identifiers"] = Array(row["identifiers"]).reject do |identifier|
        identifier.fetch("scheme").start_with?("statcan.")
      end
      Array(row["statcan_geographies"]).each do |geography|
        geography["boundary_type"] = "csd"
        geography["role"] = "governs"
        geography["province_code"] = "48"
      end
    end
    board = rows.find { |row| row.fetch("canonical_id") == "ca/ab/special-areas-board" }
    raise "Special Areas Board is missing" unless board

    board["institution_type"] = "board"
    board["government_level"] = "provincial"
    board["municipality_type"] = "Provincial Crown agency and local authority"
    board["description_en"] =
      "Crown agency that provides municipal services and public-land administration for Special Areas No. 2, 3 and 4."
  end

  def add_predecessors!(base, batch)
    rows = base.fetch("municipalities")
    report_rows = batch.fetch("municipalities")
    PREDECESSORS.each do |predecessor|
      rows << {
        "official_name" => predecessor.fetch("official_name"),
        "canonical_id" => predecessor.fetch("canonical_id"),
        "municipality_type" => "Town",
        "institution_type" => "government",
        "government_level" => "municipal",
        "status" => "dissolved",
        "active_to" => "2022-12-31",
        "website_url" => "https://www.diamondvalley.town/",
        "website_source_url" => CHANGE_SOURCE_URL,
        "source_languages" => [ "en" ],
        "description_en" =>
          "Dissolved on January 1, 2023 and amalgamated into the Town of Diamond Valley under Alberta municipal change code evidence.",
        "identifiers" => [
          {
            "scheme" => "ab.municipal_code",
            "value" => predecessor.fetch("municipal_code"),
            "preferred" => true,
            "source_url" => CHANGE_SOURCE_URL
          }
        ],
        "statcan_csd_uids" => [ predecessor.fetch("statcan_uid") ],
        "statcan_geographies" => [
          {
            "uid" => predecessor.fetch("statcan_uid"),
            "name" => predecessor.fetch("statcan_name"),
            "boundary_type" => "csd",
            "role" => "governs",
            "province_code" => "48"
          }
        ],
        "financial_statements" => [],
        "annual_reports" => [],
        "contact" => {},
        "sources" => []
      }
      statements, gaps = historical_statements(predecessor)
      report_rows << {
        "canonical_id" => predecessor.fetch("canonical_id"),
        "searched_locations" => (2000..2022).map { |year| statement_url(predecessor, year) },
        "gaps" => gaps,
        "financial_statements" => statements,
        "annual_reports" => []
      }
    end
    rows.sort_by! { |row| row.fetch("canonical_id") }
    report_rows.sort_by! { |row| row.fetch("canonical_id") }
  end

  def add_dissolved_improvement_district!(base, batch)
    canonical_id = "ca/ab/improvement-district-no-349"
    base.fetch("municipalities") << {
      "official_name" => "Improvement District No. 349",
      "canonical_id" => canonical_id,
      "municipality_type" => "Improvement District",
      "institution_type" => "government",
      "government_level" => "municipal",
      "status" => "dissolved",
      "active_from" => "2012-01-01",
      "active_to" => "2021-04-30",
      "website_url" => "https://www.alberta.ca/improvement-districts",
      "website_source_url" =>
        IMPROVEMENT_DISTRICT_CHANGE_SOURCE_URL,
      "source_languages" => [ "en" ],
      "description_en" =>
        "Dissolved May 1, 2021; its lands were annexed to the Municipal District of Bonnyville No. 87.",
      "identifiers" => [ {
        "scheme" => "ab.municipal_code", "value" => "5411", "preferred" => true,
          "source_url" =>
            IMPROVEMENT_DISTRICT_CHANGE_SOURCE_URL
      } ],
      "statcan_csd_uids" => [], "statcan_geographies" => [],
      "financial_statements" => [], "annual_reports" => [], "contact" => {}, "sources" => []
    }
    batch.fetch("municipalities") << {
      "canonical_id" => canonical_id,
      "searched_locations" => [],
      "gaps" => [ "No authoritative public statement archive was identified before dissolution." ],
      "financial_statements" => [], "annual_reports" => []
    }
  end

  def add_metis_settlements!(base, batch)
    METIS_SETTLEMENTS.each do |name, code|
      canonical_id = "ca/ab/#{slugify(name)}-metis-settlement"
      official_name = "#{name} Metis Settlement"
      base.fetch("municipalities") << {
        "official_name" => official_name,
        "canonical_id" => canonical_id,
        "municipality_type" => "Metis Settlement corporation",
        "institution_type" => "government",
        "government_level" => "metis",
        "status" => "active",
        "website_url" => nil,
        "website_source_url" => METIS_SOURCE_URL,
        "source_languages" => [ "en" ],
        "description_en" =>
          "One of Alberta's eight Metis Settlement local governments established under the Metis Settlements Act.",
        "identifiers" => [ {
          "scheme" => "ab.metis_settlement_code", "value" => code, "preferred" => true,
          "source_url" => METIS_SOURCE_URL
        } ],
        "statcan_csd_uids" => [], "statcan_geographies" => [],
        "financial_statements" => [], "annual_reports" => [], "contact" => {}, "sources" => []
      }
      batch.fetch("municipalities") << {
        "canonical_id" => canonical_id,
        "searched_locations" => [ METIS_SOURCE_URL ],
        "gaps" => [ "No centralized public audited-statement collection was identified." ],
        "financial_statements" => [], "annual_reports" => []
      }
    end
    base.fetch("municipalities").sort_by! { |row| row.fetch("canonical_id") }
    batch.fetch("municipalities").sort_by! { |row| row.fetch("canonical_id") }
  end

  def add_relationships!(base)
    relationships = Array(base["relationships"])
    PREDECESSORS.each do |predecessor|
      relationships << {
        "source_id" => "ca/ab/diamond-valley",
        "target_id" => predecessor.fetch("canonical_id"),
        "relationship_type" => "succeeds",
        "valid_from" => "2023-01-01",
        "source_url" => CHANGE_SOURCE_URL,
        "notes" => "Town of Diamond Valley formed by amalgamation on January 1, 2023."
      }
    end
    relationships << {
      "source_id" => "ca/ab/special-areas-board",
      "target_id" => "ca/ab",
      "relationship_type" => "controlled_by",
      "ownership_basis" => "statutory",
      "source_url" => SPECIAL_AREAS_SOURCE_URL,
      "notes" => "The Special Areas Board is a Crown agency governed under the Special Areas Act."
    }
    relationships << {
      "source_id" => "ca/ab/bonnyville-no-87",
      "target_id" => "ca/ab/improvement-district-no-349",
      "relationship_type" => "succeeds",
      "valid_from" => "2021-05-01",
      "source_url" => IMPROVEMENT_DISTRICT_CHANGE_SOURCE_URL,
      "notes" => "Improvement District No. 349 dissolved and its lands were annexed into the Municipal District of Bonnyville No. 87."
    }
    base["relationships"] = relationships.sort_by do |row|
      [ row.fetch("source_id"), row.fetch("relationship_type"), row.fetch("target_id") ]
    end
  end

  def historical_statements(predecessor)
    statements = []
    gaps = []
    (2000..2022).each do |year|
      url = statement_url(predecessor, year)
      body = fetch(url)
      next unless body&.start_with?("%PDF-")

      asset = archive_pdf(body)
      statements << asset.merge(
        "canonical_id" => predecessor.fetch("canonical_id"),
        "title" => "#{predecessor.fetch('official_name')} Audited Financial Statements — December 31, #{year}",
        "document_type" => "financial-statements",
        "document_variant" => "consolidated",
        "fiscal_period_start" => "#{year}-01-01",
        "fiscal_period_end" => "#{year}-12-31",
        "source_page_url" => CHANGE_SOURCE_URL,
        "download_url" => url,
        "languages" => [ "en" ],
        "retrieved_at" => @retrieved_at.iso8601,
        "rights_status" => "metadata_only",
        "notes" => "Official Alberta Municipal Affairs audited-financial-statement archive."
      )
    rescue StandardError => error
      gaps << "#{year}: #{error.message}"
    end
    [ statements, gaps ]
  end

  def statement_url(predecessor, year)
    "#{STATEMENT_ROOT}/#{year}_FS_#{predecessor.fetch('filename_name')}_#{predecessor.fetch('municipal_code')}.pdf"
  end

  def archive_pdf(body)
    sha256 = Digest::SHA256.hexdigest(body)
    relative = Pathname("sha256").join(sha256[0, 2], "#{sha256}.pdf")
    path = @asset_root.join(relative)
    path.dirname.mkpath
    path.binwrite(body) unless path.exist?
    {
      "content_sha256" => sha256,
      "byte_size" => body.bytesize,
      "mime_type" => "application/pdf",
      "archive_path" => relative.to_s
    }
  end

  def freeze_change_source!
    body = fetch(CHANGE_SOURCE_URL)
    raise "municipal change source is not a PDF" unless body&.start_with?("%PDF-")

    @output_dir.join("raw", "alberta-municipal-changes-2023.pdf").binwrite(body)
  end

  def fetch(url, redirects: 5)
    raise "too many redirects for #{url}" if redirects.negative?

    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Build Canada public-institution ontology archival scraper/1.0"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: 15, read_timeout: 60) { |http| http.request(request) }
    return fetch(URI.join(url, response["location"]).to_s, redirects: redirects - 1) if response.is_a?(Net::HTTPRedirection)
    return nil if response.is_a?(Net::HTTPNotFound)
    raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def report_summary(rows)
    documents = rows.flat_map { |row| Array(row["financial_statements"]) + Array(row["annual_reports"]) }
    {
      "financial_statement_assets" => documents.count { |row| row["document_type"] == "financial-statements" },
      "annual_report_assets" => documents.count { |row| row["document_type"] == "annual-report" },
      "municipalities_with_reports" => rows.count do |row|
        Array(row["financial_statements"]).any? || Array(row["annual_reports"]).any?
      end,
      "municipalities_with_gaps" => rows.count { |row| Array(row["gaps"]).any? }
    }
  end

  def read_json(path)
    JSON.parse(path.read)
  end

  def write_json(path, payload)
    path.write(JSON.pretty_generate(payload) << "\n")
  end

  def slugify(value)
    value.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
  end
end

options = {
  input_dir: "/Volumes/floppy/york_factory/public_institutions/sources/ab-municipalities/2026-08-20",
  output_dir: "/Volumes/floppy/york_factory/public_institutions/sources/ab-municipalities/2026-08-21",
  release_date: "2026-08-21",
  retrieved_at: "2026-08-21T00:00:00Z",
  asset_root: "/Volumes/floppy/york_factory/public_institutions/assets"
}
OptionParser.new do |parser|
  parser.on("--input-dir PATH") { |value| options[:input_dir] = value }
  parser.on("--output-dir PATH") { |value| options[:output_dir] = value }
  parser.on("--release-date DATE") { |value| options[:release_date] = value }
  parser.on("--retrieved-at TIME") { |value| options[:retrieved_at] = value }
  parser.on("--asset-root PATH") { |value| options[:asset_root] = value }
end.parse!

summary = AlbertaNationalReleaseAugmenter.new(**options).call
puts JSON.pretty_generate(summary)
