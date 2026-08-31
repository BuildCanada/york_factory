#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "time"

class EnrichNlMunicipalManifest
  GENERATED_AT = "2026-08-24T12:00:00Z"
  NAME_OVERRIDES = {
    "harbour-main-chapels-cove-lakeview" => "ca/nl/harbour-main-chapel-s-cove",
    "long-harbour-mount-arlington-heights" => "ca/nl/long-harbour-mount-arlington",
    "lushes-bight-beaumont-beaumont-north" => "ca/nl/lushes-bight-beaumont-beaumont",
    "mount-carmel-mitchells-brook-st-catherines" => "ca/nl/mount-carmel-mitchells-brook-st",
    "port-au-port-west-aguathuna-felix-cove" => "ca/nl/port-au-port-west-aguathuna-felix",
    "small-point-adams-cove-blackhead-broad-cove" => "ca/nl/small-point-adam-s-cove-blackhead",
    "st-vincents-st-stephens-peters-river" => "ca/nl/st-vincent-s-st-stephen-s-peter-s"
  }.freeze

  def initialize(input_manifest:, metadata_path:, output_path:, release_version:)
    @input_manifest = File.expand_path(input_manifest)
    @metadata_path = File.expand_path(metadata_path)
    @output_path = File.expand_path(output_path)
    @release_version = release_version
  end

  def run
    raise "refusing to overwrite #{@output_path}" if File.exist?(@output_path)

    payload = JSON.parse(File.read(@input_manifest))
    metadata = JSON.parse(File.read(@metadata_path))
    rows = payload.fetch("municipalities")
    by_name = rows.group_by { |row| normalize_name(row.fetch("official_name_en")) }
    by_id = rows.to_h { |row| [ row.fetch("canonical_id"), row ] }
    matches = match_records(metadata.fetch("records"), by_name, by_id)
    raise "expected 276 unique profile matches, found #{matches.length}" unless matches.length == 276

    matches.each { |record, row| enrich_row!(row, record) }
    update_release_metadata!(payload)
    update_coverage!(payload, rows)
    write_output(payload, matches)
  end

  private

  def match_records(records, by_name, by_id)
    used_ids = {}
    records.to_h do |record|
      key = normalize_name(record.fetch("name"))
      candidates = by_name.fetch(key, [])
      row = candidates.one? ? candidates.first : by_id[NAME_OVERRIDES[record.fetch("slug")]]
      raise "no unique manifest match for #{record.fetch('name')}" unless row
      raise "duplicate manifest match for #{row.fetch('canonical_id')}" if used_ids[row.fetch("canonical_id")]

      used_ids[row.fetch("canonical_id")] = true
      [ record, row ]
    end
  end

  def enrich_row!(row, record)
    row["official_name_en"] = record.fetch("name")
    row["website_source_url"] = record.fetch("profile_url")
    row["website_status"] = record.fetch("website_status")
    if record["website_url"]
      row["website_url"] = record.fetch("website_url")
      row["scrape_gaps"] = Array(row["scrape_gaps"]).reject { |gap| gap.include?("website URL") }
    end

    row["contact"] = {
      "email" => record.fetch("emails").first,
      "phone" => record.fetch("phones").first,
      "mailing_address" => mailing_address(record)
    }.compact
    row["identifiers"] = Array(row["identifiers"])
    row["identifiers"] << {
      "scheme" => "mnl.directory_id",
      "value" => record.fetch("directory_id").to_s,
      "preferred" => false
    }
    row["identifiers"].uniq! { |identifier| [ identifier.fetch("scheme"), identifier.fetch("value") ] }
  end

  def mailing_address(record)
    text = record["contact_text"].to_s
    text = text.delete_prefix("Contact Information ")
    record.fetch("phones").each { |phone| text = text.sub(/\s*#{Regexp.escape(phone)}\s*\z/, "") }
    text = text.strip
    text.empty? ? nil : text
  end

  def update_release_metadata!(payload)
    payload["release_version"] = @release_version
    payload["effective_on"] = @release_version
    payload["published_at"] = "#{@release_version}T12:00:00Z"
    payload["source_retrieved_at"] = GENERATED_AT
    payload["derived_from_release_manifest"] = @input_manifest
    payload["metadata_enrichment_source"] = {
      "publisher" => "Municipalities Newfoundland and Labrador",
      "title" => "Municipal Directory",
      "url" => "https://municipalnl.ca/directory/",
      "retrieved_at" => GENERATED_AT,
      "sha256" => Digest::SHA256.file(@metadata_path).hexdigest
    }
  end

  def update_coverage!(payload, rows)
    website_count = rows.count { |row| row["website_url"] }
    coverage = payload.fetch("coverage").find { |row| row.fetch("subject") == "websites" }
    coverage["status"] = website_count == rows.length ? "complete" : "partial"
    coverage["notes"] = "#{website_count} of #{rows.length} institutions have a verified official website URL. " \
      "The current MNL directory also supplied email and phone metadata for 273 incorporated municipalities or Inuit community governments."
    coverage["source_url"] = "https://municipalnl.ca/directory/"
  end

  def write_output(payload, matches)
    FileUtils.mkdir_p(File.dirname(@output_path))
    File.write(@output_path, JSON.pretty_generate(payload) << "\n")
    summary = {
      "release_version" => @release_version,
      "matched_profiles" => matches.length,
      "verified_websites" => matches.count { |record, _row| record["website_url"] },
      "contacts_with_email" => matches.count { |record, _row| record.fetch("emails").any? },
      "contacts_with_phone" => matches.count { |record, _row| record.fetch("phones").any? },
      "output" => @output_path,
      "sha256" => Digest::SHA256.file(@output_path).hexdigest
    }
    puts JSON.pretty_generate(summary)
  end

  def normalize_name(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.delete("'").gsub(/\b(town|city|municipality|local service district|inuit community government)\b/, " ")
      .gsub(/[^a-z0-9]+/, " ").strip
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: enrich_nl_municipal_manifest.rb --input-manifest PATH --metadata PATH --output PATH --release-version YYYY-MM-DD"
  parser.on("--input-manifest PATH") { |value| options[:input_manifest] = value }
  parser.on("--metadata PATH") { |value| options[:metadata_path] = value }
  parser.on("--output PATH") { |value| options[:output_path] = value }
  parser.on("--release-version VERSION") { |value| options[:release_version] = value }
end.parse!

missing = %i[input_manifest metadata_path output_path release_version].reject { |key| options[key] }
abort "missing options: #{missing.join(', ')}" if missing.any?

EnrichNlMunicipalManifest.new(**options).run
