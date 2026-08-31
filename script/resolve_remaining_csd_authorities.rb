#!/usr/bin/env ruby

require "json"
require "optparse"
require "pathname"
require "time"

options = {
  release_version: "2026-08-24",
  retrieved_at: "2026-08-24T12:00:00Z"
}
OptionParser.new do |parser|
  parser.on("--first-nations-manifest PATH") { |value| options[:first_nations_manifest] = value }
  parser.on("--first-nations-output PATH") { |value| options[:first_nations_output] = value }
  parser.on("--saskatchewan-manifest PATH") { |value| options[:saskatchewan_manifest] = value }
  parser.on("--saskatchewan-output PATH") { |value| options[:saskatchewan_output] = value }
  parser.on("--crosswalk-output PATH") { |value| options[:crosswalk_output] = value }
  parser.on("--release-version DATE") { |value| options[:release_version] = value }
  parser.on("--retrieved-at TIMESTAMP") { |value| options[:retrieved_at] = value }
end.parse!

required = %i[
  first_nations_manifest first_nations_output saskatchewan_manifest saskatchewan_output crosswalk_output
]
missing = required.select { |key| options[key].nil? }
abort "Missing options: #{missing.map { |key| "--#{key.to_s.tr('_', '-')}" }.join(', ')}" if missing.any?

def write_json(path, payload)
  path = Pathname(path)
  path.dirname.mkpath
  path.write("#{JSON.pretty_generate(payload)}\n")
end

first_nations_path = Pathname(options.fetch(:first_nations_manifest))
first_nations = JSON.parse(first_nations_path.read)
abort "First Nations release mismatch" unless first_nations.fetch("release_version") == options.fetch(:release_version)

nisgaa_source = {
  "key" => "nisgaa_lisims_government",
  "canonical_id" => "ca/sources/fn/nisgaa-lisims-government",
  "publisher" => "Nisg̱a’a Lisims Government",
  "title_en" => "Nisg̱a’a Lisims Government",
  "url" => "https://www.nisgaanation.ca/government/",
  "retrieved_at" => options.fetch(:retrieved_at),
  "languages" => [ "en" ]
}
unless first_nations.fetch("sources").any? { |source| source.fetch("key") == nisgaa_source.fetch("key") }
  first_nations.fetch("sources") << nisgaa_source
end
first_nations["indigenous_governments"] = Array(first_nations["indigenous_governments"])
first_nations["indigenous_governments"].reject! do |government|
  government["canonical_id"] == "ca/fn/nisgaa-lisims-government"
end
first_nations["indigenous_governments"] << {
  "canonical_id" => "ca/fn/nisgaa-lisims-government",
  "name_en" => "Nisg̱a’a Lisims Government",
  "name_fr" => nil,
  "institution_type" => "government",
  "government_level" => "first_nation",
  "legal_form" => "Modern treaty self-government",
  "status" => "active",
  "website_url" => "https://www.nisgaanation.ca/government/",
  "source_key" => "nisgaa_lisims_government",
  "contact" => {
    "phone" => "250-633-3000",
    "mailing_address" => "PO Box 231, 2000 Lisims Drive, New Aiyansh, BC V0J 1A0"
  },
  "provenance" => {
    "source_url" => "https://www.nisgaanation.ca/government/nisgaa-lisims-government/government-structure/",
    "retrieved_at" => options.fetch(:retrieved_at)
  }
}
first_nations["derived_from_release_manifest"] = first_nations_path.to_s
write_json(options.fetch(:first_nations_output), first_nations)

saskatchewan_path = Pathname(options.fetch(:saskatchewan_manifest))
saskatchewan = JSON.parse(saskatchewan_path.read)
abort "Saskatchewan release mismatch" unless saskatchewan.fetch("release_version") == options.fetch(:release_version)
saskatchewan.fetch("municipalities").reject! do |municipality|
  municipality["canonical_id"] == "ca/sk/northern-saskatchewan-administration-district"
end
saskatchewan.fetch("municipalities") << {
  "canonical_id" => "ca/sk/northern-saskatchewan-administration-district",
  "official_name_en" => "Northern Saskatchewan Administration District",
  "official_name_fr" => nil,
  "municipality_type" => "northern_district",
  "tier" => "district",
  "institution_type" => "government",
  "government_level" => "municipal",
  "status" => "active",
  "website_url" => "https://www.planningforgrowthnorthsk.com/northern-settlements.html",
  "website_source_url" => "https://www.planningforgrowthnorthsk.com/northern-settlements.html",
  "website_status" => "verified_official_program_site",
  "source_languages" => [ "en" ],
  "description_en" => "Municipality administered by Northern Municipal Services; it acts as the local government authority for northern settlements in consultation with elected local advisory committees.",
  "identifiers" => [],
  "statcan_geographies" => [],
  "documents" => []
}
saskatchewan["derived_from_release_manifest"] = saskatchewan_path.to_s
saskatchewan["coverage"] = Array(saskatchewan["coverage"]) + [ {
  "scope_id" => "ca/sk/northern-saskatchewan-administration-district",
  "subject" => "institutions",
  "status" => "complete",
  "notes" => "Northern Saskatchewan Administration District added from the official Northern Municipal Services program directory.",
  "source_url" => "https://www.planningforgrowthnorthsk.com/northern-settlements.html"
} ]
write_json(options.fetch(:saskatchewan_output), saskatchewan)

sources = [
  {
    "key" => "qc_mamh_municipal_directory",
    "canonical_id" => "ca/sources/qc/mamh-municipal-directory",
    "publisher_name" => "Ministère des Affaires municipales et de l’Habitation",
    "title_en" => "Quebec municipal directory",
    "title_fr" => "Répertoire des municipalités",
    "url" => "https://www.mamh.gouv.qc.ca/repertoire-des-municipalites/",
    "retrieved_at" => options.fetch(:retrieved_at),
    "license" => nil,
    "languages" => [ "fr" ]
  },
  {
    "key" => "isc_first_nation_profiles",
    "canonical_id" => "ca/sources/isc/first-nation-profiles",
    "publisher_name" => "Indigenous Services Canada",
    "title_en" => "First Nation Profiles",
    "title_fr" => "Profils des Premières Nations",
    "url" => "https://services.sac-isc.gc.ca/fnp/Main/Search/SearchFN.aspx",
    "retrieved_at" => options.fetch(:retrieved_at),
    "license" => nil,
    "languages" => [ "en", "fr" ]
  },
  {
    "key" => "maanulth_final_agreement",
    "canonical_id" => "ca/sources/bc/maa-nulth-final-agreement-appendices",
    "publisher_name" => "Government of British Columbia",
    "title_en" => "Maa-nulth First Nations Final Agreement Appendices",
    "title_fr" => nil,
    "url" => "https://www2.gov.bc.ca/assets/gov/environment/natural-resource-stewardship/consulting-with-first-nations/agreements/maa-nulth_final_agreement_appendices_english-2009.pdf",
    "retrieved_at" => options.fetch(:retrieved_at),
    "license" => nil,
    "languages" => [ "en" ]
  },
  {
    "key" => "nrcan_legislative_lands",
    "canonical_id" => "ca/sources/nrcan/legislative-land-boundaries",
    "publisher_name" => "Natural Resources Canada",
    "title_en" => "Aboriginal Lands of Canada Legislative Boundaries",
    "title_fr" => "Limites législatives des terres autochtones du Canada",
    "url" => "https://open.canada.ca/data/en/dataset/522b07b9-78e2-4819-b736-ad9208eb1067",
    "retrieved_at" => options.fetch(:retrieved_at),
    "license" => "Open Government Licence - Canada",
    "languages" => [ "en", "fr" ]
  },
  {
    "key" => "nisgaa_lisims_government",
    "canonical_id" => "ca/sources/fn/nisgaa-lisims-government",
    "publisher_name" => "Nisg̱a’a Lisims Government",
    "title_en" => "Nisg̱a’a Government structure",
    "title_fr" => nil,
    "url" => "https://www.nisgaanation.ca/government/nisgaa-lisims-government/government-structure/",
    "retrieved_at" => options.fetch(:retrieved_at),
    "license" => nil,
    "languages" => [ "en" ]
  },
  {
    "key" => "sk_northern_settlements",
    "canonical_id" => "ca/sources/sk/northern-settlements",
    "publisher_name" => "Northern Municipal Services",
    "title_en" => "Northern settlements",
    "title_fr" => nil,
    "url" => "https://www.planningforgrowthnorthsk.com/northern-settlements.html",
    "retrieved_at" => options.fetch(:retrieved_at),
    "license" => nil,
    "languages" => [ "en" ]
  }
]

mappings = []
add = lambda do |uid, institution_id, source_key, notes, role = "governs"|
  mappings << {
    "csd_uid" => uid,
    "institution_id" => institution_id,
    "role" => role,
    "source_key" => source_key,
    "match_method" => "authoritative_crosswalk",
    "confidence" => 1.0,
    "valid_from" => nil,
    "valid_to" => nil,
    "notes" => notes
  }
end

{
  "2499877" => "kuujjuarapik", "2499878" => "umiujaq", "2499879" => "inukjuak",
  "2499883" => "akulivik", "2499885" => "ivujivik", "2499887" => "salluit",
  "2499888" => "kangiqsujuaq", "2499889" => "quaqtaq", "2499890" => "kangirsuk",
  "2499891" => "aupaluk", "2499892" => "tasiujaq", "2499893" => "kuujjuaq",
  "2499894" => "kangiqsualujjuaq"
}.each do |uid, slug|
  add.call(uid, "ca/qc/#{slug}", "qc_mamh_municipal_directory",
    "Quebec's official municipal directory identifies the northern village government with this name.")
end

{
  "2485803" => "ca/fn/wolf-lake",
  "2485804" => "ca/fn/long-point-first-nation",
  "2489802" => "ca/fn/communaute-anicinape-de-kitcisakik",
  "2498802" => "ca/fn/montagnais-de-pakua-shipi",
  "3558076" => "ca/fn/aroland",
  "3560081" => "ca/fn/neskantaga-first-nation",
  "3560086" => "ca/fn/nibinamik-first-nation",
  "3560091" => "ca/fn/weenusk",
  "4623039" => "ca/fn/mathias-colomb",
  "4817854" => "ca/fn/dene-tha",
  "4817855" => "ca/fn/bigstone-cree-nation",
  "5933803" => "ca/fn/upper-nicola",
  "5957804" => "ca/fn/dease-river",
  "5957813" => "ca/fn/liard-first-nation"
}.each do |uid, institution_id|
  add.call(uid, institution_id, "isc_first_nation_profiles",
    "Curated reconciliation of the named Indigenous settlement or reserve to its governing First Nation.")
end

{
  "5923803" => "ca/fn/huu-ay-aht-first-nations",
  "5923804" => "ca/fn/ucluelet-first-nation",
  "5923805" => "ca/fn/uchucklesaht",
  "5923807" => "ca/fn/ucluelet-first-nation",
  "5923809" => "ca/fn/huu-ay-aht-first-nations",
  "5923810" => "ca/fn/toquaht",
  "5923814" => "ca/fn/huu-ay-aht-first-nations",
  "5924806" => "ca/fn/ka-yu-k-t-h-che-k-tles7et-h-first-nations",
  "5924813" => "ca/fn/ka-yu-k-t-h-che-k-tles7et-h-first-nations"
}.each do |uid, institution_id|
  add.call(uid, institution_id, "maanulth_final_agreement",
    "The treaty appendices identify this former reserve as land of the named Maa-nulth First Nation.")
end

add.call("5949035", "ca/fn/nisgaa-lisims-government", "nisgaa_lisims_government",
  "The Nisg̱a’a Nation's official government structure identifies Nisg̱a’a Lisims Government as its central government.")
add.call("4718825", "ca/sk/northern-saskatchewan-administration-district", "sk_northern_settlements",
  "Northern Municipal Services states that the District is the municipality and local government authority for northern settlements including Brabant Lake.", "administers")

{
  "6001007" => "ca/fn/teslin-tlingit-council",
  "6001008" => "ca/fn/carcross-tagish-first-nation",
  "6001010" => "ca/fn/ta-an-kwach-an",
  "6001019" => "ca/fn/champagne-and-aishihik-first-nations",
  "6001031" => "ca/fn/tr-ondek-hwech-in",
  "6001038" => "ca/fn/champagne-and-aishihik-first-nations"
}.each do |uid, institution_id|
  add.call(uid, institution_id, "nrcan_legislative_lands",
    "Authoritative legislative-land geometry and name reconciliation identify the governing Yukon First Nation.")
end

abort "Expected 44 remaining mappings, generated #{mappings.length}" unless mappings.length == 44
duplicates = mappings.map { |mapping| [ mapping.fetch("csd_uid"), mapping.fetch("institution_id"), mapping.fetch("role") ] }
abort "Duplicate authority mappings" unless duplicates.uniq.length == duplicates.length

crosswalk = {
  "release_version" => options.fetch(:release_version),
  "geography_vintage" => 2021,
  "sources" => sources,
  "mappings" => mappings.sort_by { |mapping| mapping.fetch("csd_uid") },
  "unresolved_csd_uids" => [],
  "derived_from" => {
    "method" => "curated_resolution_of_previously_unresolved_indigenous_and_northern_csd_authorities",
    "generated_at" => Time.now.utc.iso8601,
    "first_nations_manifest" => first_nations_path.to_s,
    "saskatchewan_manifest" => saskatchewan_path.to_s
  }
}
write_json(options.fetch(:crosswalk_output), crosswalk)

puts JSON.generate(
  first_nations_governments: first_nations.fetch("bands").length + first_nations.fetch("indigenous_governments").length,
  saskatchewan_institutions: saskatchewan.fetch("municipalities").length,
  authority_mappings: mappings.length
)
