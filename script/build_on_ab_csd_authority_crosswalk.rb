#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"

output_path = ARGV.fetch(0) do
  abort "Usage: build_on_ab_csd_authority_crosswalk.rb OUTPUT_PATH"
end
abort "Refusing to overwrite #{output_path}" if File.exist?(output_path)

sources = [
  {
    "key" => "on_roster_statcan",
    "canonical_id" => "ca/sources/crosswalk/on-roster-statcan/2026-08-22",
    "publisher_name" => "Ontario Ministry of Municipal Affairs and Housing; Statistics Canada",
    "title_en" => "Ontario municipality roster to 2021 census subdivision reconciliation",
    "title_fr" => nil,
    "url" => "https://www.ontario.ca/page/list-ontario-municipalities",
    "retrieved_at" => "2026-08-21T12:00:00Z",
    "license" => "Open Government Licence - Ontario",
    "languages" => [ "en" ]
  },
  {
    "key" => "ab_roster_statcan",
    "canonical_id" => "ca/sources/crosswalk/ab-roster-statcan/2026-08-22",
    "publisher_name" => "Alberta Municipal Affairs; Statistics Canada",
    "title_en" => "Alberta municipality roster to 2021 census subdivision reconciliation",
    "title_fr" => nil,
    "url" => "https://municipalaffairs.gov.ab.ca/mc_financial_tax_bylaws.cfm",
    "retrieved_at" => "2026-08-21T00:00:00Z",
    "license" => nil,
    "languages" => [ "en" ]
  }
]

on_mappings = {
  "3525005" => [ "ca/on/hamilton-city", "City and township share the CSD name; legal type identifies the City of Hamilton." ],
  "3514019" => [ "ca/on/hamilton-township", "City and township share the CSD name; legal type identifies the Township of Hamilton." ],
  "3513020" => [ "ca/on/prince-edward", "Official roster name and county legal type match the 2021 CSD." ],
  "3502025" => [ "ca/on/the-nation-municipality", "Official bilingual municipality name matches the 2021 CSD." ],
  "3556077" => [ "ca/on/mattice-val-ca-ta", "Official municipality name matches the 2021 CSD Mattice-Val Côté." ],
  "3558016" => [ "ca/on/oconnor", "Official township name matches the 2021 CSD O'Connor." ],
  "3557014" => [ "ca/on/tarbutt", "Current Township of Tarbutt corresponds to the 2021 CSD Tarbutt and Tarbutt Additional." ],
  "3549022" => [ "ca/on/burks-falls", "Official village name matches the 2021 CSD Burk's Falls." ]
}.map do |csd_uid, (institution_id, notes)|
  {
    "csd_uid" => csd_uid,
    "institution_id" => institution_id,
    "role" => "governs",
    "source_key" => "on_roster_statcan",
    "match_method" => "exact_name",
    "confidence" => 0.95,
    "valid_from" => nil,
    "valid_to" => nil,
    "notes" => notes
  }
end

ab_mapping = {
  "csd_uid" => "4812038",
  "institution_id" => "ca/ab/improvement-district-no-349",
  "role" => "governs",
  "source_key" => "ab_roster_statcan",
  "match_method" => "exact_name",
  "confidence" => 0.95,
  "valid_from" => nil,
  "valid_to" => nil,
  "notes" => "Official improvement-district name and number exactly match the 2021 CSD."
}

payload = {
  "release_version" => "2026-08-22",
  "geography_vintage" => 2021,
  "sources" => sources,
  "mappings" => on_mappings + [ ab_mapping ]
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload) + "\n")
puts JSON.generate(path: output_path, mappings: payload.fetch("mappings").length)
