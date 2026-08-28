#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"

audit_path, output_path = ARGV
abort "Usage: build_nt_designated_authority_csd_crosswalk.rb AUDIT_PATH OUTPUT_PATH" unless audit_path && output_path
abort "Refusing to overwrite #{output_path}" if File.exist?(output_path)

audit = JSON.parse(File.read(audit_path))
rows = audit.fetch("designated_authority_exclusions")
source_url = rows.map { |row| row.fetch("source_url") }.uniq.fetch(0)

payload = {
  "release_version" => "2026-08-22",
  "geography_vintage" => 2021,
  "sources" => [
    {
      "key" => "nt_maca_designated_authorities",
      "canonical_id" => "ca/sources/crosswalk/nt-maca-designated-authorities/2026-08-22",
      "publisher_name" => "Government of the Northwest Territories, Municipal and Community Affairs",
      "title_en" => "First Nation designated authorities delivering municipal-type services",
      "title_fr" => nil,
      "url" => source_url,
      "retrieved_at" => "2026-08-22T12:00:00Z",
      "license" => nil,
      "languages" => [ "en" ]
    }
  ],
  "mappings" => rows.sort_by { |row| row.fetch("service_area_csd_uid") }.map do |row|
    {
      "csd_uid" => row.fetch("service_area_csd_uid"),
      "institution_id" => row.fetch("existing_canonical_id"),
      "role" => "governs",
      "source_key" => "nt_maca_designated_authorities",
      "match_method" => "source_assertion",
      "confidence" => 1.0,
      "valid_from" => nil,
      "valid_to" => nil,
      "notes" => "#{row.fetch('authority_name')} is the designated authority delivering municipal-type services for #{row.fetch('service_community')}; the existing ca/fn institution is reused instead of duplicating the legal authority."
    }
  end
}

raise "duplicate CSD mappings" unless payload.fetch("mappings").map { |row| row.fetch("csd_uid") }.uniq.length == rows.length

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload) + "\n")
puts JSON.generate(path: output_path, mappings: payload.fetch("mappings").length)
