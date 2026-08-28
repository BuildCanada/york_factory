#!/usr/bin/env ruby

require "date"
require "dbf"
require "digest"
require "json"
require "optparse"
require "pathname"
require "time"

class StatcanCsdInventoryBuilder
  EXPECTED_COUNT = 5_161
  SOURCE_URL = "https://open.canada.ca/data/en/dataset/ef70dc3b-1069-4037-9bce-61f47e628a1d"

  def initialize(dbf_path:, source_zip_path:, output_path:, release_version:, retrieved_at:)
    @dbf_path = Pathname(dbf_path).expand_path
    @source_zip_path = Pathname(source_zip_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @release_version = Date.iso8601(release_version).iso8601
    @retrieved_at = Time.iso8601(retrieved_at).utc
  end

  def call
    raise ArgumentError, "output already exists: #{@output_path}" if @output_path.exist?

    rows = read_rows
    raise ArgumentError, "expected #{EXPECTED_COUNT} CSDs, found #{rows.length}" unless rows.length == EXPECTED_COUNT
    duplicates = rows.map { |row| row.fetch("geo_uid") }.tally.select { |_uid, count| count > 1 }
    raise ArgumentError, "duplicate CSD UIDs: #{duplicates.keys.join(', ')}" if duplicates.any?

    payload = {
      "product" => "statcan-csd-authority-inventory",
      "release_version" => @release_version,
      "geography_vintage" => 2021,
      "geographic_reference_on" => "2021-01-01",
      "retrieved_at" => @retrieved_at.iso8601,
      "source" => {
        "canonical_id" => "ca/sources/statcan/csd-2021-cartographic-boundaries",
        "publisher_name" => "Statistics Canada",
        "title_en" => "2021 Census subdivision cartographic boundaries",
        "url" => SOURCE_URL,
        "license" => "Statistics Canada Open Licence",
        "languages" => [ "en", "fr" ],
        "source_zip_sha256" => Digest::SHA256.file(@source_zip_path).hexdigest,
        "source_dbf_sha256" => Digest::SHA256.file(@dbf_path).hexdigest
      },
      "expected_csd_count" => EXPECTED_COUNT,
      "csds" => rows
    }
    @output_path.dirname.mkpath
    @output_path.write(JSON.pretty_generate(payload) << "\n")
    @output_path
  end

  private

  def read_rows
    rows = []
    DBF::Table.new(@dbf_path.to_s).each do |record|
      attributes = record.attributes
      rows << {
        "geo_uid" => attributes.fetch("CSDUID"),
        "dguid" => attributes.fetch("DGUID"),
        "name_en" => clean(attributes.fetch("CSDNAME")),
        "classification_type" => clean(attributes.fetch("CSDTYPE")),
        "province_code" => attributes.fetch("PRUID"),
        "area_sq_km" => attributes.fetch("LANDAREA")
      }
    end
    rows.sort_by { |row| row.fetch("geo_uid") }
  end

  def clean(value)
    value.to_s.encode("UTF-8", invalid: :replace, undef: :replace).strip
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.on("--dbf PATH") { |value| options[:dbf_path] = value }
    parser.on("--source-zip PATH") { |value| options[:source_zip_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--release-version DATE") { |value| options[:release_version] = value }
    parser.on("--retrieved-at TIME") { |value| options[:retrieved_at] = value }
  end.parse!
  required = %i[dbf_path source_zip_path output_path release_version retrieved_at]
  missing = required.reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?
  puts StatcanCsdInventoryBuilder.new(**options).call
end
