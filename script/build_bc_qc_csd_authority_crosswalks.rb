#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "set"

release_version = "2026-08-22"
root = ENV.fetch("PUBLIC_INSTITUTIONS_ROOT", "/Volumes/floppy/york_factory/public_institutions/sources")
bc_release_path = File.join(root, "bc-municipalities", release_version, "release-manifest.json")
qc_release_path = File.join(root, "qc-local-governments", release_version, "release-manifest.json")
csd_inventory_path = File.join(root, "statcan", "sgc-2021", "releases", release_version, "csd-inventory.json")
fn_release_path = File.join(root, "first-nations", "releases", "2026-08-21", "normalized-manifest.json")

bc_output_path = ARGV[0] || File.join(root, "bc-municipalities", release_version, "csd-authority-crosswalk.json")
qc_output_path = ARGV[1] || File.join(root, "qc-local-governments", release_version, "csd-authority-crosswalk.json")
bc_audit_path = bc_output_path.sub(/\.json\z/, "-audit.json")
qc_audit_path = qc_output_path.sub(/\.json\z/, "-audit.json")
output_paths = [ bc_output_path, qc_output_path, bc_audit_path, qc_audit_path ]
existing = output_paths.select { File.exist?(_1) }
abort "Refusing to overwrite: #{existing.join(', ')}" if existing.any?

bc_release = JSON.parse(File.read(bc_release_path))
qc_release = JSON.parse(File.read(qc_release_path))
inventory = JSON.parse(File.read(csd_inventory_path)).fetch("csds")
fn_release = JSON.parse(File.read(fn_release_path))

bc_institution_ids = bc_release.fetch("municipalities").map { _1.fetch("canonical_id") }.to_set
fn_rows = fn_release["bands"] || fn_release["first_nations"] || fn_release["institutions"] || fn_release["organizations"] || []
fn_institution_ids = fn_rows.map { _1["canonical_id"] || _1["id"] }.compact.to_set
qc_institutions = qc_release.fetch("municipalities")
qc_institution_ids = qc_institutions.map { _1.fetch("canonical_id") }.to_set

bc_regional_districts_by_cd = {}
bc_release.fetch("municipalities").each do |institution|
  next unless institution["jurisdiction_kind"] == "regional_district"

  institution.fetch("statcan_geographies", []).select { _1["boundary_type"] == "cd" }.each do |geography|
    bc_regional_districts_by_cd.fetch(geography.fetch("uid"), nil) and
      abort "Duplicate B.C. regional-district authority for CD #{geography.fetch('uid')}"
    bc_regional_districts_by_cd[geography.fetch("uid")] = institution.fetch("canonical_id")
  end
end

bc_rdas = inventory.select do |csd|
  csd["province_code"] == "59" && csd["classification_type"] == "RDA"
end
bc_rda_mappings = bc_rdas.filter_map do |csd|
  institution_id = bc_regional_districts_by_cd[csd.fetch("geo_uid")[0, 4]]
  next unless institution_id

  {
    "csd_uid" => csd.fetch("geo_uid"),
    "institution_id" => institution_id,
    "role" => "governs",
    "source_key" => "bc_regional_district_electoral_areas",
    "match_method" => "authoritative_crosswalk",
    "confidence" => 1.0,
    "valid_from" => nil,
    "valid_to" => nil,
    "notes" => "The 2021 SGC hierarchy places this electoral-area CSD in the census division represented by the regional district; B.C. identifies regional districts as the local governments for electoral areas."
  }
end

bc_treaty_land_mappings = [
  {
    "csd_uid" => "5915802",
    "institution_id" => "ca/fn/tsawwassen-first-nation",
    "role" => "governs",
    "source_key" => "bc_tsawwassen_final_agreement",
    "match_method" => "authoritative_crosswalk",
    "confidence" => 1.0,
    "valid_from" => "2009-04-03",
    "valid_to" => nil,
    "notes" => "Statistics Canada defines the TWL CSD as treaty land transferred to Tsawwassen First Nation; the Final Agreement establishes Tsawwassen Government as its government."
  },
  {
    "csd_uid" => "5927802",
    "institution_id" => "ca/fn/tla-amin-nation",
    "role" => "governs",
    "source_key" => "bc_tlaamin_final_agreement",
    "match_method" => "authoritative_crosswalk",
    "confidence" => 1.0,
    "valid_from" => "2016-04-05",
    "valid_to" => nil,
    "notes" => "Statistics Canada defines the TAL CSD as treaty land transferred to Tla'amin Nation; the Final Agreement establishes Tla'amin Government as its government."
  }
]

bc_treaty_land_mappings.each do |mapping|
  abort "Missing First Nation institution #{mapping.fetch('institution_id')}" unless fn_institution_ids.include?(mapping.fetch("institution_id"))
end
bc_rda_mappings.each do |mapping|
  abort "Missing B.C. institution #{mapping.fetch('institution_id')}" unless bc_institution_ids.include?(mapping.fetch("institution_id"))
end

bc_sources = [
  {
    "key" => "bc_regional_district_electoral_areas",
    "canonical_id" => "ca/sources/crosswalk/bc-regional-district-electoral-areas/#{release_version}",
    "publisher_name" => "Government of British Columbia; Statistics Canada",
    "title_en" => "Regional districts and 2021 census geography hierarchy",
    "title_fr" => nil,
    "url" => "https://www2.gov.bc.ca/gov/content/governments/local-governments/facts-framework/systems/regional-districts",
    "retrieved_at" => "2026-08-22T12:00:00Z",
    "license" => "Open Government Licence - British Columbia; Statistics Canada Open Licence",
    "languages" => [ "en" ]
  },
  {
    "key" => "bc_tsawwassen_final_agreement",
    "canonical_id" => "ca/sources/bc-laws/tsawwassen-final-agreement/#{release_version}",
    "publisher_name" => "King's Printer, Government of British Columbia; Statistics Canada",
    "title_en" => "Tsawwassen First Nation Final Agreement and 2021 census subdivision definition",
    "title_fr" => nil,
    "url" => "https://www.bclaws.gov.bc.ca/civix/document/id/complete/statreg/07039_19",
    "retrieved_at" => "2026-08-22T12:00:00Z",
    "license" => nil,
    "languages" => [ "en" ]
  },
  {
    "key" => "bc_tlaamin_final_agreement",
    "canonical_id" => "ca/sources/bc-laws/tlaamin-final-agreement/#{release_version}",
    "publisher_name" => "King's Printer, Government of British Columbia; Statistics Canada",
    "title_en" => "Tla'amin Final Agreement and 2021 census subdivision definition",
    "title_fr" => nil,
    "url" => "https://www.bclaws.gov.bc.ca/civix/document/id/complete/statreg/13002_18",
    "retrieved_at" => "2026-08-22T12:00:00Z",
    "license" => nil,
    "languages" => [ "en" ]
  }
]

bc_unmapped = inventory.select { _1["province_code"] == "59" }.reject do |csd|
  (bc_rda_mappings + bc_treaty_land_mappings).any? { _1["csd_uid"] == csd["geo_uid"] } ||
    bc_release.fetch("municipalities").any? do |institution|
      institution.fetch("statcan_geographies", []).any? do |geography|
        geography["boundary_type"] == "csd" && geography["uid"] == csd["geo_uid"]
      end
    end
end

bc_payload = {
  "release_version" => release_version,
  "geography_vintage" => 2021,
  "sources" => bc_sources,
  "mappings" => (bc_rda_mappings + bc_treaty_land_mappings).sort_by { _1.fetch("csd_uid") },
  "unresolved_csd_uids" => bc_unmapped.map { _1.fetch("geo_uid") }.sort
}

organized_qc_types = %w[CT CU GR MÉ PE V VC VK VL VN].freeze
qc_by_current_code = {}
qc_institutions.reject { _1.fetch("canonical_id").include?("/regional/") }.each do |institution|
  institution.fetch("identifiers", []).select { _1["scheme"] == "qc.code-geographique" }.each do |identifier|
    code = identifier.fetch("value").to_s.rjust(5, "0")
    abort "Duplicate current Quebec geographic code #{code}" if qc_by_current_code.key?(code)
    qc_by_current_code[code] = institution
  end
end

# Official Quebec territorial-history records identify each old code's merger successor.
qc_successors = {
  "2411020" => "ca/qc/lac-des-aigles",
  "2413060" => "ca/qc/lac-des-aigles",
  "2414080" => "ca/qc/la-pocatiere",
  "2414085" => "ca/qc/la-pocatiere",
  "2414090" => "ca/qc/la-pocatiere",
  "2429025" => "ca/qc/courcelles-saint-evariste",
  "2430090" => "ca/qc/courcelles-saint-evariste",
  "2432040" => "ca/qc/plessisville",
  "2432045" => "ca/qc/plessisville",
  "2482010" => "ca/qc/notre-dame-de-la-salette",
  "2488010" => "ca/qc/la-morandiere-rochebaucourt",
  "2488015" => "ca/qc/la-morandiere-rochebaucourt",
  "2488055" => "ca/qc/amos",
  "2488060" => "ca/qc/amos",
  "2493020" => "ca/qc/hebertville",
  "2493025" => "ca/qc/hebertville",
  "2493030" => "ca/qc/hebertville"
}.freeze

qc_organized_csds = inventory.select do |csd|
  csd["province_code"] == "24" && organized_qc_types.include?(csd["classification_type"])
end
qc_mappings = qc_organized_csds.map do |csd|
  csd_uid = csd.fetch("geo_uid")
  successor_id = qc_successors[csd_uid]
  institution = successor_id ? qc_institutions.find { _1["canonical_id"] == successor_id } : qc_by_current_code[csd_uid[-5, 5]]
  abort "No organized Quebec authority for #{csd_uid} #{csd.fetch('name_en')}" unless institution
  abort "Missing Quebec institution #{institution.fetch('canonical_id')}" unless qc_institution_ids.include?(institution.fetch("canonical_id"))

  if successor_id
    {
      "csd_uid" => csd_uid,
      "institution_id" => institution.fetch("canonical_id"),
      "role" => "governs",
      "source_key" => "qc_territorial_history",
      "match_method" => "authoritative_crosswalk",
      "confidence" => 1.0,
      "valid_from" => nil,
      "valid_to" => nil,
      "notes" => "The 2021 CSD represents a predecessor territory now governed by #{institution.fetch('official_name_fr')}; Quebec's official territorial history records the predecessor-to-successor code transaction."
    }
  else
    {
      "csd_uid" => csd_uid,
      "institution_id" => institution.fetch("canonical_id"),
      "role" => "governs",
      "source_key" => "qc_mamh_municipal_directory",
      "match_method" => "authoritative_crosswalk",
      "confidence" => 1.0,
      "valid_from" => nil,
      "valid_to" => nil,
      "notes" => "The institution's official five-digit Quebec geographic code equals the CSD component of the 2021 seven-digit SGC code."
    }
  end
end.sort_by { _1.fetch("csd_uid") }

qc_residual = inventory.select { _1["province_code"] == "24" }.reject do |csd|
  qc_mappings.any? { _1["csd_uid"] == csd["geo_uid"] }
end

qc_sources = [
  {
    "key" => "qc_mamh_municipal_directory",
    "canonical_id" => "ca/sources/qc/mamh/municipal-directory/#{release_version}",
    "publisher_name" => "Ministère des Affaires municipales et de l'Habitation",
    "title_en" => "Quebec municipality directory (French-language source)",
    "title_fr" => "Répertoire des municipalités du Québec",
    "url" => "https://www.donneesquebec.ca/recherche/fr/dataset/repertoire-des-municipalites-du-quebec",
    "retrieved_at" => qc_release.fetch("source_retrieved_at"),
    "license" => "CC BY 4.0",
    "languages" => [ "fr" ]
  },
  {
    "key" => "qc_territorial_history",
    "canonical_id" => "ca/sources/qc/isq/territorial-history/#{release_version}",
    "publisher_name" => "Institut de la statistique du Québec",
    "title_en" => "Territorial Division Directory and history of municipal changes",
    "title_fr" => "Répertoire des divisions territoriales et historique des modifications municipales",
    "url" => "https://statistique.quebec.ca/statistiques/divisions-territoriales/fichiers_code_geo/code-geographique-quebec.html",
    "retrieved_at" => "2026-08-22T12:00:00Z",
    "license" => nil,
    "languages" => [ "en", "fr" ]
  }
]

qc_payload = {
  "release_version" => release_version,
  "geography_vintage" => 2021,
  "sources" => qc_sources,
  "mappings" => qc_mappings,
  "unresolved_csd_uids" => qc_residual.map { _1.fetch("geo_uid") }.sort
}

invalid_qc_links = []
inventory_by_uid = inventory.to_h { [ _1.fetch("geo_uid"), _1 ] }
qc_institutions.each do |institution|
  institution.fetch("statcan_geographies", []).select { _1["boundary_type"] == "csd" }.each do |geography|
    csd = inventory_by_uid[geography.fetch("uid")]
    next unless csd

    is_regional_entity = institution.fetch("canonical_id").include?("/regional/")
    is_excluded_land_type = !organized_qc_types.include?(csd.fetch("classification_type"))
    next unless is_regional_entity || is_excluded_land_type

    invalid_qc_links << {
      "csd_uid" => csd.fetch("geo_uid"),
      "csd_name" => csd.fetch("name_en"),
      "csd_type" => csd.fetch("classification_type"),
      "institution_id" => institution.fetch("canonical_id"),
      "reason" => is_regional_entity ? "Regional MRC/administration name collision is not a CSD authority link." : "Reserve or unorganized CSD was linked by name without land-authority evidence."
    }
  end
end

bc_audit = {
  "release_version" => release_version,
  "geography_vintage" => 2021,
  "input_counts" => {
    "bc_csds" => inventory.count { _1["province_code"] == "59" },
    "regional_district_electoral_area_csds" => bc_rdas.length
  },
  "output_counts" => {
    "new_authority_mappings" => bc_payload.fetch("mappings").length,
    "regional_district_electoral_area_mappings" => bc_rda_mappings.length,
    "treaty_land_mappings" => bc_treaty_land_mappings.length,
    "residual_after_existing_release_and_crosswalk" => bc_unmapped.length
  },
  "residual_by_type" => bc_unmapped.group_by { _1.fetch("classification_type") }.transform_values(&:length).sort.to_h,
  "unmapped_organized_exceptions" => [
    {
      "csd_uid" => "5957001",
      "name" => "Stikine Region",
      "type" => "RDA",
      "reason" => "The 2021 SGC places this CSD in Stikine census division, but B.C. has no regional district institution for Stikine Region in the release."
    },
    {
      "csd_uid" => "5949035",
      "name" => "Nisga'a",
      "type" => "NL",
      "reason" => "The combined release lacks the central Nisga'a Lisims Government institution; village or unrelated First Nation authorities must not substitute for it."
    }
  ]
}

qc_existing_csd_uids = qc_institutions.flat_map do |institution|
  institution.fetch("statcan_geographies", []).select { _1["boundary_type"] == "csd" }.map { _1.fetch("uid") }
end.uniq
qc_new_count = qc_mappings.count { !qc_existing_csd_uids.include?(_1.fetch("csd_uid")) }
qc_audit = {
  "release_version" => release_version,
  "geography_vintage" => 2021,
  "input_counts" => {
    "qc_csds" => inventory.count { _1["province_code"] == "24" },
    "organized_municipal_csds" => qc_organized_csds.length
  },
  "output_counts" => {
    "authoritative_organized_mappings" => qc_mappings.length,
    "newly_resolved_organized_csds" => qc_new_count,
    "confirmed_existing_organized_csds" => qc_mappings.length - qc_new_count,
    "predecessor_or_recoded_csd_mappings" => qc_successors.length,
    "residual_reserve_or_unorganized_csds" => qc_residual.length,
    "invalid_existing_name_links" => invalid_qc_links.length
  },
  "residual_by_type" => qc_residual.group_by { _1.fetch("classification_type") }.transform_values(&:length).sort.to_h,
  "invalid_existing_name_links" => invalid_qc_links.sort_by { [ _1.fetch("csd_uid"), _1.fetch("institution_id") ] },
  "predecessor_or_recoded_mappings" => qc_mappings.select { _1["source_key"] == "qc_territorial_history" }
}

{
  bc_output_path => bc_payload,
  qc_output_path => qc_payload,
  bc_audit_path => bc_audit,
  qc_audit_path => qc_audit
}.each do |path, payload|
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

puts JSON.generate(
  bc_path: bc_output_path,
  bc_mappings: bc_payload.fetch("mappings").length,
  qc_path: qc_output_path,
  qc_mappings: qc_payload.fetch("mappings").length
)
