#!/usr/bin/env ruby
# frozen_string_literal: true

require "csv"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "open3"
require "optparse"
require "pathname"
require "time"
require "uri"

class NtNuLocalGovernmentAugmenter
  RELEASE_DATE = "2026-08-22"
  RETRIEVED_AT = "2026-08-22T12:00:00Z"
  STATCAN_URL = "https://www.statcan.gc.ca/en/subjects/standard/sgc/2021/index"
  MACA_ROSTER_URL = "https://www.maca.gov.nt.ca/en/communitylist"
  NU_ROSTER_URL = "https://www.nunavutlegislation.ca/en/consolidated-law/hamlets-act-consolidation"

  NT_CSD_NAMES = {
    "ca/nt/aklavik" => [ "6101025", "Aklavik" ],
    "ca/nt/behchoko" => [ "6103031", "Behchokò" ],
    "ca/nt/deline-gotine-government" => [ "6102003", "Déline" ],
    "ca/nt/enterprise" => [ "6105003", "Enterprise" ],
    "ca/nt/fort-liard" => [ "6104009", "Fort Liard" ],
    "ca/nt/fort-mcpherson" => [ "6101015", "Fort McPherson" ],
    "ca/nt/fort-providence" => [ "6104014", "Fort Providence" ],
    "ca/nt/fort-resolution" => [ "6105018", "Fort Resolution" ],
    "ca/nt/fort-simpson" => [ "6104038", "Fort Simpson" ],
    "ca/nt/fort-smith" => [ "6105001", "Fort Smith" ],
    "ca/nt/gameti" => [ "6103049", "Gamètì" ],
    "ca/nt/hay-river" => [ "6105016", "Hay River" ],
    "ca/nt/inuvik" => [ "6101017", "Inuvik" ],
    "ca/nt/kasho-gotine" => [ "6102009", "Fort Good Hope" ],
    "ca/nt/norman-wells" => [ "6102007", "Norman Wells" ],
    "ca/nt/paulatuk" => [ "6101014", "Paulatuk" ],
    "ca/nt/sachs-harbour" => [ "6101041", "Sachs Harbour" ],
    "ca/nt/tsiigehtchic" => [ "6101010", "Tsiigehtchic" ],
    "ca/nt/tuktoyaktuk" => [ "6101036", "Tuktoyaktuk" ],
    "ca/nt/tulita" => [ "6102005", "Tulita" ],
    "ca/nt/ulukhaktok" => [ "6101095", "Ulukhaktok" ],
    "ca/nt/wekweeti" => [ "6103052", "Wekweètì" ],
    "ca/nt/whati" => [ "6103034", "Whatì" ],
    "ca/nt/yellowknife" => [ "6106023", "Yellowknife" ]
  }.freeze

  NT_WEBSITES = {
    "ca/nt/behchoko" => "https://www.tlicho.ca/community/behchoko",
    "ca/nt/enterprise" => "https://enterprise-nt.ca/",
    "ca/nt/fort-mcpherson" => "https://www.fortmcpherson.ca/",
    "ca/nt/gameti" => "https://www.tlicho.ca/community/gameti",
    "ca/nt/kasho-gotine" => "https://fortgoodhope.ca/",
    "ca/nt/tuktoyaktuk" => "https://tuktoyaktuk.ca/",
    "ca/nt/tulita" => "https://tulitahamlet.ca/",
    "ca/nt/wekweeti" => "https://www.tlicho.ca/community/wekweeti",
    "ca/nt/whati" => "https://www.tlicho.ca/community/whati"
  }.freeze

  NT_SPECIAL_METADATA = {
    "ca/nt/deline-gotine-government" => {
      "governance_model" => "inclusive_aboriginal_public_government",
      "description_en" => "Inclusive Aboriginal public government exercising municipal functions and self-government powers in the Délı̨nę District."
    },
    "ca/nt/behchoko" => { "governance_model" => "tlicho_public_community_government" },
    "ca/nt/gameti" => { "governance_model" => "tlicho_public_community_government" },
    "ca/nt/wekweeti" => { "governance_model" => "tlicho_public_community_government" },
    "ca/nt/whati" => { "governance_model" => "tlicho_public_community_government" },
    "ca/nt/kasho-gotine" => { "governance_model" => "charter_community_government" },
    "ca/nt/enterprise" => {
      "governance_model" => "public_municipal_government",
      "administrative_status" => "under_supervision",
      "administrative_status_source_url" => "https://www.gov.nt.ca/en/newsroom/enterprise-set-return-local-governance-under-one-year-supervision"
    }
  }.freeze

  NT_DESIGNATED_AUTHORITIES = [
    [ "Colville Lake", "Behdzi Ahda First Nation", "771", "ca/fn/behdzi-ahda-first-nation", "6102012" ],
    [ "Kakisa", "Ka'a'gee Tu First Nation", "768", "ca/fn/ka-a-gee-tu-first-nation", "6104005" ],
    [ "Hay River Dene 1", "Kátł’odeeche First Nation", "761", "ca/fn/k-atlodeeche-first-nation", "6104017" ],
    [ "Nahanni Butte", "Nahanni Butte Dene Band", "766", "ca/fn/nahanni-butte", "6104010" ],
    [ "Wrigley", "Pehdzeh Ki First Nation", "756", "ca/fn/pehdzeh-ki-first-nation", "6104044" ],
    [ "Sambaa K’e", "Sambaa K’e First Nation", "767", "ca/fn/sambaa-k-e-first-nation", "6104006" ],
    [ "Jean Marie River", "Tthets’éhk’édélı̨ First Nation", "770", "ca/fn/jean-marie-river-first-nation", "6104013" ],
    [ "Lutselk'e", "Łutsel K’e Dene First Nation", "764", "ca/fn/lutsel-k-e-dene-first-nation", "6105020" ],
    [ "Dettah", "Yellowknives Dene First Nation (Dettah)", "763", "ca/fn/yellowknives-dene-first-nation", "6106021" ]
  ].freeze

  NT_PREDECESSOR_OVERLAPS = [
    [ "ca/nt/deline-gotine-government", "ca/fn/deline-first-nation", "The Délı̨nę Dene Band was replaced by the Délı̨nę Got’ı̨nę Government on the self-government agreement's effective date." ],
    [ "ca/nt/behchoko", "ca/fn/dog-rib-rae", "The Tłı̨chǫ community government replaced the former Indian Act band and municipal corporation." ],
    [ "ca/nt/gameti", "ca/fn/gameti-first-nation", "The Tłı̨chǫ community government replaced the former Indian Act band and municipal corporation." ],
    [ "ca/nt/wekweeti", "ca/fn/dechi-laot-i-first-nations", "The Tłı̨chǫ community government replaced the former Indian Act band and municipal corporation." ],
    [ "ca/nt/whati", "ca/fn/wha-ti-first-nation", "The Tłı̨chǫ community government replaced the former Indian Act band and municipal corporation." ]
  ].freeze

  NU_CSD_NAMES = {
    "ca/nu/arctic-bay" => [ "6204018", "Arctic Bay" ],
    "ca/nu/arviat" => [ "6205015", "Arviat" ],
    "ca/nu/baker-lake" => [ "6205023", "Baker Lake" ],
    "ca/nu/cambridge-bay" => [ "6208073", "Cambridge Bay" ],
    "ca/nu/chesterfield-inlet" => [ "6205019", "Chesterfield Inlet" ],
    "ca/nu/clyde-river" => [ "6204015", "Clyde River" ],
    "ca/nu/coral-harbour" => [ "6205014", "Coral Harbour" ],
    "ca/nu/gjoa-haven" => [ "6208081", "Gjoa Haven" ],
    "ca/nu/grise-fiord" => [ "6204025", "Grise Fiord" ],
    "ca/nu/igloolik" => [ "6204012", "Igloolik" ],
    "ca/nu/iqaluit" => [ "6204003", "Iqaluit" ],
    "ca/nu/kimmirut" => [ "6204005", "Kimmirut" ],
    "ca/nu/kinngait" => [ "6204007", "Cape Dorset" ],
    "ca/nu/kugaaruk" => [ "6208047", "Kugaaruk" ],
    "ca/nu/kugluktuk" => [ "6208059", "Kugluktuk" ],
    "ca/nu/naujaat" => [ "6205027", "Naujaat" ],
    "ca/nu/pangnirtung" => [ "6204009", "Pangnirtung" ],
    "ca/nu/pond-inlet" => [ "6204020", "Pond Inlet" ],
    "ca/nu/qikiqtarjuaq" => [ "6204010", "Qikiqtarjuaq" ],
    "ca/nu/rankin-inlet" => [ "6205017", "Rankin Inlet" ],
    "ca/nu/resolute" => [ "6204022", "Resolute" ],
    "ca/nu/sanikiluaq" => [ "6204001", "Sanikiluaq" ],
    "ca/nu/sanirajak" => [ "6204011", "Hall Beach" ],
    "ca/nu/taloyoak" => [ "6208087", "Taloyoak" ],
    "ca/nu/whale-cove" => [ "6205016", "Whale Cove" ]
  }.freeze

  NU_LEGAL_NAMES = NU_CSD_NAMES.keys.to_h do |canonical_id|
    place = canonical_id.split("/").last.split("-").map(&:capitalize).join(" ")
    place = "Gjoa Haven" if canonical_id == "ca/nu/gjoa-haven"
    place = "Iqaluit" if canonical_id == "ca/nu/iqaluit"
    place = "Qikiqtarjuaq" if canonical_id == "ca/nu/qikiqtarjuaq"
    place = "Resolute Bay" if canonical_id == "ca/nu/resolute"
    [ canonical_id, canonical_id == "ca/nu/iqaluit" ? "City of Iqaluit" : "Hamlet of #{place}" ]
  end.freeze

  NU_WEBSITES = {
    "ca/nu/arviat" => "https://www.arviat.ca/",
    "ca/nu/baker-lake" => "https://www.bakerlake.ca/",
    "ca/nu/cambridge-bay" => "https://www.cambridgebay.ca/",
    "ca/nu/chesterfield-inlet" => "https://chesterfield-inlet.ca/",
    "ca/nu/clyde-river" => "https://clyderiver.ca/",
    "ca/nu/coral-harbour" => "https://coralharbour.ca/",
    "ca/nu/gjoa-haven" => "https://gjoahaven.ca/",
    "ca/nu/grise-fiord" => "https://www.grisefiord.ca/",
    "ca/nu/igloolik" => "https://igloolik.ca/",
    "ca/nu/iqaluit" => "https://www.iqaluit.ca/",
    "ca/nu/kimmirut" => "https://www.kimmirut.ca/",
    "ca/nu/kinngait" => "https://kinngait.net/",
    "ca/nu/kugluktuk" => "https://www.kugluktuk.ca/",
    "ca/nu/pangnirtung" => "https://www.pangnirtung.ca/",
    "ca/nu/pond-inlet" => "https://pondinlet.ca/",
    "ca/nu/rankin-inlet" => "https://rankininlet.ca/",
    "ca/nu/resolute" => "https://resolutebay.diligent.community/",
    "ca/nu/sanikiluaq" => "https://www.sanikiluaq.ca/",
    "ca/nu/whale-cove" => "https://www.whalecove.ca/"
  }.freeze

  NU_CONTINUATION_ORDERS = {
    "ca/nu/arctic-bay" => "R.R.N.W.T. 1990, c. H-2", "ca/nu/arviat" => "R.R.N.W.T. 1990, c. H-3",
    "ca/nu/baker-lake" => "R.R.N.W.T. 1990, c. H-4", "ca/nu/qikiqtarjuaq" => "R.R.N.W.T. 1990, c. H-5",
    "ca/nu/cambridge-bay" => "R.R.N.W.T. 1990, c. H-6", "ca/nu/kinngait" => "R.R.N.W.T. 1990, c. H-7",
    "ca/nu/chesterfield-inlet" => "R.R.N.W.T. 1990, c. H-8", "ca/nu/clyde-river" => "R.R.N.W.T. 1990, c. H-9",
    "ca/nu/kugluktuk" => "R.R.N.W.T. 1990, c. H-10", "ca/nu/coral-harbour" => "R.R.N.W.T. 1990, c. H-11",
    "ca/nu/gjoa-haven" => "R.R.N.W.T. 1990, c. H-17", "ca/nu/grise-fiord" => "R.R.N.W.T. 1990, c. H-18",
    "ca/nu/sanirajak" => "R.R.N.W.T. 1990, c. H-19", "ca/nu/igloolik" => "R.R.N.W.T. 1990, c. H-21",
    "ca/nu/kimmirut" => "R.R.N.W.T. 1990, c. H-23", "ca/nu/pangnirtung" => "R.R.N.W.T. 1990, c. H-24",
    "ca/nu/kugaaruk" => "R.R.N.W.T. 1990, c. H-26", "ca/nu/pond-inlet" => "R.R.N.W.T. 1990, c. H-27",
    "ca/nu/rankin-inlet" => "R.R.N.W.T. 1990, c. H-29", "ca/nu/naujaat" => "R.R.N.W.T. 1990, c. H-30",
    "ca/nu/resolute" => "R.R.N.W.T. 1990, c. H-31", "ca/nu/sanikiluaq" => "R.R.N.W.T. 1990, c. H-33",
    "ca/nu/taloyoak" => "R.R.N.W.T. 1990, c. H-34", "ca/nu/whale-cove" => "R.R.N.W.T. 1990, c. H-36",
    "ca/nu/iqaluit" => "R.R.N.W.T. 1990, c. C-9"
  }.freeze

  NU_NAME_STATUS_ORDERS = {
    "ca/nu/kinngait" => "R-002-2020", "ca/nu/sanirajak" => "R-003-2020",
    "ca/nu/kimmirut" => "R-191-96", "ca/nu/kugaaruk" => "R-047-99",
    "ca/nu/kugluktuk" => "R-192-96", "ca/nu/qikiqtarjuaq" => "R-137-98",
    "ca/nu/taloyoak" => "R-060-92", "ca/nu/iqaluit" => "R-005-2001"
  }.freeze

  OFFICIAL_EVIDENCE = {
    "nt" => {
      "maca-community-list.html" => MACA_ROSTER_URL,
      "maca-community-contact-listing.html" => "https://www.maca.gov.nt.ca/en/community-contact-listing",
      "maca-community-government-types.html" => "https://www.maca.gov.nt.ca/en/services/community-land-use-planning-and-development",
      "gnwt-tlicho-governance.html" => "https://www.eia.gov.nt.ca/en/priorities/concluding-and-implementing-land-and-resources-and-self-government-agreements/tlicho",
      "gnwt-deline-governance.html" => "https://www.eia.gov.nt.ca/en/priorities/concluding-and-implementing-land-and-resources-and-self-government-agreements/deline",
      "tlicho-community-government-act.pdf" => "https://www.justice.gov.nt.ca/en/files/legislation/tlicho-community-government/tlicho-community-government.a.pdf",
      "enterprise-supervision.html" => "https://www.gov.nt.ca/en/newsroom/enterprise-set-return-local-governance-under-one-year-supervision"
    },
    "nu" => {
      "hamlets-act.html" => NU_ROSTER_URL,
      "cities-towns-villages-act.html" => "https://www.nunavutlegislation.ca/en/consolidated-law/cities-towns-and-villages-act-consolidation",
      "current-regulations.pdf" => "https://www.nunavutlegislation.ca/en/file-download/download/public/3884",
      "kinngait-sanirajak-name-orders.pdf" => "https://www.nunavutlegislation.ca/en/file-download/download/public/3728",
      "gn-hamlet-directory.pdf" => "https://www.gov.nu.ca/sites/default/files/documents/2023-12/ELCC%20Licensed%20Daycare%20Handbook%20-%20EN.pdf",
      "cra-registered-municipalities.html" => "https://www.canada.ca/en/revenue-agency/services/charities-giving/other-organizations-that-issue-donation-receipts-qualified-donees/other-qualified-donees-listings/list-municipalities-nunavut.html"
    }
  }.freeze

  def initialize(root:, release_date: RELEASE_DATE, download: true)
    @root = Pathname(root)
    @release_date = release_date
    @download = download
  end

  def run
    %w[nt nu].each { |code| build_jurisdiction(code) }
  end

  private

  def build_jurisdiction(code)
    source_dir = @root.join("#{code}-local-governments", "2026-08-21")
    target_dir = @root.join("#{code}-local-governments", @release_date)
    raise "immutable release already exists: #{target_dir}" if target_dir.exist?
    raise "missing 2026-08-21 base release: #{source_dir}" unless source_dir.directory?

    staging = Pathname("#{target_dir}.staging-#{Process.pid}")
    FileUtils.mkdir_p(staging.join("raw", "frozen-2026-08-21"))
    FileUtils.cp_r(source_dir.join("raw", "."), staging.join("raw", "frozen-2026-08-21"))

    base_release = JSON.parse(source_dir.join("release-manifest.json").read)
    base_normalized = JSON.parse(source_dir.join("normalized-local-governments.json").read)
    release_rows = enrich_rows(code, base_release.fetch("municipalities"), normalized: false)
    normalized_rows = enrich_rows(code, base_normalized.fetch("institutions"), normalized: true)
    validate!(code, release_rows, normalized_rows)

    audit = code == "nt" ? nwt_audit : nunavut_audit
    write_json(staging.join("classification-audit.json"), audit)
    write_json(staging.join("raw", "first-nations-cross-roster-audit.json"), audit)
    raw_manifest, failures = archive_evidence(code, staging, release_rows)
    add_frozen_raw_records(source_dir, staging, raw_manifest)
    raw_manifest.each do |record|
      record["path"] = record.fetch("path").sub(staging.to_s, target_dir.to_s)
    end

    release = build_release(code, base_release, release_rows, failures)
    normalized = build_normalized(code, base_normalized, normalized_rows, failures, release.fetch("scrape_gaps"))
    write_json(staging.join("release-manifest.json"), release)
    write_json(staging.join("normalized-local-governments.json"), normalized)
    write_json(staging.join("raw-manifest.json"), raw_manifest.sort_by { |row| row.fetch("path") })
    write_json(staging.join("scrape-summary.json"), summary(code, staging, release, failures))
    File.rename(staging, target_dir)
    puts "wrote #{target_dir}"
  end

  def enrich_rows(code, rows, normalized:)
    rows.map do |input|
      row = deep_copy(input)
      canonical_id = row.fetch("canonical_id")
      if code == "nt"
        enrich_nt_row(row, canonical_id, normalized: normalized)
      else
        enrich_nu_row(row, canonical_id, normalized: normalized)
      end
      row
    end.sort_by { |row| row.fetch("canonical_id") }
  end

  def enrich_nt_row(row, canonical_id, normalized:)
    profile_url = row["source_url"] || row["website_source_url"]
    website = canonical_id == "ca/nt/aklavik" ? nil : (NT_WEBSITES[canonical_id] || row["website_url"])
    apply_website(row, website, website || row["website_source_url"] || row["source_url"])
    profile_path = URI(profile_url).path.sub(%r{\A/en/content/}, "") if profile_url&.include?("maca.gov.nt.ca/en/content/")
    row["identifiers"] = [ identifier("gnwt.maca.community-profile", profile_path, profile_url) ].compact
    row.merge!(NT_SPECIAL_METADATA.fetch(canonical_id, { "governance_model" => "public_municipal_government" }))
    geography = geography_row("61", NT_CSD_NAMES.fetch(canonical_id), profile_url || MACA_ROSTER_URL, normalized: normalized)
    set_geographies(row, [ geography ], normalized: normalized)
  end

  def enrich_nu_row(row, canonical_id, normalized:)
    row["official_name_en"] = NU_LEGAL_NAMES.fetch(canonical_id)
    row[normalized ? "legal_form" : "municipality_type"] = canonical_id == "ca/nu/iqaluit" ? "city" : "hamlet"
    row["institution_kind"] = "municipal_government" if normalized
    row["governance_model"] = "public_municipal_government"
    row["community_character"] = "Inuit-majority community; the municipal corporation is a public government, not an Inuit rights-holding organization."
    website = NU_WEBSITES[canonical_id]
    apply_website(row, website, website || row["source_url"] || NU_ROSTER_URL)
    legal_source = canonical_id == "ca/nu/iqaluit" ? "https://www.nunavutlegislation.ca/en/consolidated-law/cities-towns-and-villages-act-consolidation" : NU_ROSTER_URL
    identifiers = [ identifier("nu.regulation", NU_CONTINUATION_ORDERS.fetch(canonical_id), legal_source, true) ]
    if NU_NAME_STATUS_ORDERS[canonical_id]
      identifiers << identifier(
        "nu.regulation", NU_NAME_STATUS_ORDERS[canonical_id],
        "https://www.nunavutlegislation.ca/en/file-download/download/public/3728", false
      )
    end
    row["identifiers"] = identifiers
    geography = geography_row("62", NU_CSD_NAMES.fetch(canonical_id), NU_ROSTER_URL, normalized: normalized)
    if %w[ca/nu/kinngait ca/nu/sanirajak].include?(canonical_id)
      geography[normalized ? "match_method" : "match_method"] = "official_2020_rename_to_2021_sgc_legacy_name"
      geography["notes"] = "The 2021 SGC classification structure retains the former CSD name; the municipal corporation was renamed by R-002-2020 or R-003-2020."
    end
    set_geographies(row, [ geography ], normalized: normalized)
  end

  def apply_website(row, website, source_url)
    row["website_url"] = website
    row["website_source_url"] = source_url
    row["website_status"] = website ? "verified_first_party" : "gap"
    gap = website ? nil : "No current first-party municipal website was verified in the dated audit."
    row["website_gap"] = gap if row.key?("website_gap")
    row["scrape_gaps"] = gap ? [ gap ] : [] if row.key?("scrape_gaps")
  end

  def identifier(scheme, value, source_url, preferred = true)
    return unless value
    { "scheme" => scheme, "value" => value, "preferred" => preferred, "source_url" => source_url }
  end

  def geography_row(province_code, (uid, name), evidence_url, normalized:)
    common = {
      "boundary_type" => "csd", "vintage" => 2021, "role" => "governs",
      "match_method" => "curated_authoritative_name_or_rename", "evidence_urls" => [ evidence_url, STATCAN_URL ],
      "notes" => "Association to frozen 2021 statistical geography; not an institution identifier."
    }
    if normalized
      common.merge("geography_id" => "ca/geography/csd-2021/#{uid}", "code_system" => "statscan.sgc2021", "geo_uid" => uid, "name" => name)
    else
      common.merge("uid" => uid, "name" => name, "province_code" => province_code)
    end
  end

  def set_geographies(row, geographies, normalized:)
    row[normalized ? "geography_associations" : "statcan_geographies"] = geographies
  end

  def build_release(code, base, rows, failures)
    roster = code == "nt" ? MACA_ROSTER_URL : NU_ROSTER_URL
    websites = rows.count { |row| row["website_url"] }
    institution_notes = if code == "nt"
      "24 current incorporated/public community governments emitted. Nine designated-authority service areas are represented by existing ca/fn band governments and are listed in classification-audit.json, not duplicated here."
    else
      "All 25 current Nunavut municipal corporations emitted: 24 hamlets and the City of Iqaluit. Inuit associations and rights-holding organizations are outside this public-municipality roster."
    end
    gaps = if code == "nt"
      [
        "Nine designated-authority communities use existing First Nation band councils for municipal-type services and are deliberately not duplicated under ca/nt; see classification-audit.json.",
        "Five ca/fn records correspond to predecessor Indian Act governments replaced by current Délı̨nę/Tłı̨chǫ public governments; see classification-audit.json.",
        "Financial statements and annual reports were outside this roster-correction pass."
      ]
    else
      [
        "No current first-party website was verified for #{rows.length - websites} of 25 municipal corporations.",
        "The 2021 SGC names Cape Dorset and Hall Beach are retained only as frozen geography labels for current Kinngait and Sanirajak.",
        "Financial statements and annual reports were outside this roster-correction pass."
      ]
    end
    base.merge(
      "release_version" => @release_date, "effective_on" => @release_date,
      "schema_version" => "1.1",
      "published_at" => RETRIEVED_AT, "source_retrieved_at" => RETRIEVED_AT,
      "municipalities" => rows, "relationships" => [],
      "coverage" => coverage(code, roster, rows.length, websites, institution_notes),
      "scrape_gaps" => gaps, "scrape_failures" => failures,
      "raw_manifest_path" => "#{code}-local-governments/#{@release_date}/raw-manifest.json"
    )
  end

  def coverage(code, roster, count, websites, institution_notes)
    scope = "ca/#{code}"
    [
      [ "institutions", "complete", institution_notes, roster ],
      [ "websites", websites == count ? "complete" : "partial", "#{websites} of #{count} institutions have a verified first-party website URL.", roster ],
      [ "geographies", "complete", "All #{count} institutions have a curated Statistics Canada SGC 2021 CSD association; legacy SGC names are retained for renamed municipalities.", STATCAN_URL ],
      [ "relationships", "complete", "No hierarchy or ownership edge is asserted between a local government and the territorial government. Cross-roster exclusions and predecessor overlaps are recorded in classification-audit.json.", roster ],
      [ "financial-statements", "not-searched", "Financial statements were outside this roster-correction pass.", roster ],
      [ "annual-reports", "not-searched", "Annual reports were outside this roster-correction pass.", roster ],
      [ "statement-of-financial-information", "not-searched", "Statement-of-financial-information records were outside this roster-correction pass.", roster ],
      [ "document-assets", "not-searched", "Document assets were outside this roster-correction pass.", roster ]
    ].map { |subject, status, notes, url| { "scope_id" => scope, "subject" => subject, "status" => status, "notes" => notes, "source_url" => url } }
  end

  def build_normalized(code, base, rows, failures, gaps)
    base.merge(
      "schema_version" => "1.1", "release_date" => @release_date, "retrieved_at" => RETRIEVED_AT,
      "institutions" => rows, "gaps" => gaps, "failures" => failures,
      "classification_audit_path" => "#{code}-local-governments/#{@release_date}/classification-audit.json"
    )
  end

  def nwt_audit
    {
      "jurisdiction" => "ca/nt", "effective_on" => @release_date,
      "included_scope" => "24 current incorporated/public community governments, including four Tłı̨chǫ community governments and the Délı̨nę inclusive Aboriginal public government.",
      "designated_authority_exclusions" => NT_DESIGNATED_AUTHORITIES.map do |community, name, band_number, canonical_id, csd_uid|
        {
          "service_community" => community, "authority_name" => name,
          "authority_kind" => "first_nation_band_council_delivering_municipal_type_services",
          "isc_band_number" => band_number, "existing_canonical_id" => canonical_id,
          "service_area_csd_uid" => csd_uid, "duplicate_legal_entity_avoided" => true,
          "source_url" => "https://www.maca.gov.nt.ca/en/services/community-land-use-planning-and-development"
        }
      end,
      "predecessor_cross_roster_overlaps" => NT_PREDECESSOR_OVERLAPS.map do |current_id, legacy_id, notes|
        { "current_canonical_id" => current_id, "legacy_ca_fn_canonical_id" => legacy_id, "relationship" => "predecessor", "notes" => notes }
      end,
      "sources" => [
        "https://www.maca.gov.nt.ca/en/services/community-land-use-planning-and-development",
        "https://www.eia.gov.nt.ca/en/priorities/concluding-and-implementing-land-and-resources-and-self-government-agreements/tlicho",
        "https://www.eia.gov.nt.ca/en/priorities/concluding-and-implementing-land-and-resources-and-self-government-agreements/deline"
      ]
    }
  end

  def nunavut_audit
    {
      "jurisdiction" => "ca/nu", "effective_on" => @release_date,
      "included_scope" => "25 public municipal corporations: 24 hamlets and the City of Iqaluit.",
      "excluded_categories" => [
        {
          "category" => "inuit_rights_holding_and_regional_organizations",
          "reason" => "They are not municipal corporations and must be represented as distinct institutions if added to the ontology."
        },
        {
          "category" => "unorganized_or_uninhabited_census_subdivisions",
          "examples" => [ "Nanisivik", "Bathurst Inlet", "Umingmaktok", "Qikiqtaaluk, Unorganized", "Kivalliq, Unorganized", "Kitikmeot, Unorganized" ],
          "reason" => "Statistics Canada geography rows are not evidence of a current municipal corporation."
        }
      ],
      "ca_fn_cross_roster_count" => 0,
      "rename_mappings" => [
        { "canonical_id" => "ca/nu/kinngait", "current_name" => "Hamlet of Kinngait", "sgc_2021_name" => "Cape Dorset", "regulation" => "R-002-2020" },
        { "canonical_id" => "ca/nu/sanirajak", "current_name" => "Hamlet of Sanirajak", "sgc_2021_name" => "Hall Beach", "regulation" => "R-003-2020" }
      ],
      "sources" => [ NU_ROSTER_URL, "https://www.nunavutlegislation.ca/en/file-download/download/public/3728" ]
    }
  end

  def archive_evidence(code, staging, rows)
    evidence = OFFICIAL_EVIDENCE.fetch(code).dup
    rows.each do |row|
      url = row["website_url"]
      evidence["websites/#{row.fetch('canonical_id').split('/').last}.html"] = url if url
      profile = row["source_url"]
      evidence["profiles/#{row.fetch('canonical_id').split('/').last}.html"] = profile if code == "nt" && profile&.include?("maca.gov.nt.ca")
    end
    return [ [], [] ] unless @download

    mutex = Mutex.new
    records = []
    failures = []
    queue = Queue.new
    evidence.each { |relative, url| queue << [ relative, url ] }
    [ 10, evidence.length ].min.times.map do
      Thread.new do
        loop do
          relative, url = queue.pop(true)
          path = staging.join("raw", relative)
          response, final_url = fetch(url)
          FileUtils.mkdir_p(path.dirname)
          path.binwrite(response.body)
          record = raw_record(path, url, final_url, response)
          mutex.synchronize { records << record }
        rescue ThreadError
          break
        rescue StandardError => error
          begin
            FileUtils.mkdir_p(path.dirname)
            _stdout, stderr, status = Open3.capture3(
              "curl", "-L", "--fail", "--max-time", "45", "--silent", "--show-error",
              "-o", path.to_s, url
            )
            raise "curl fallback failed: #{stderr.strip}" unless status.success?
            content_type = path.extname == ".pdf" ? "application/pdf" : "text/html"
            record = raw_record_for_file(path, url, content_type)
            mutex.synchronize { records << record }
          rescue StandardError => fallback_error
            mutex.synchronize do
              failures << {
                "url" => url, "error_class" => error.class.name,
                "message" => "#{error.message}; #{fallback_error.message}"
              }
            end
          end
        end
      end
    end.each(&:join)
    [ records, failures ]
  end

  def fetch(url, redirects = 8)
    raise "too many redirects for #{url}" if redirects.zero?
    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "YorkFactoryPublicInstitutions/1.0 (research archive)"
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 15
    http.read_timeout = 25
    response = http.request(request)
    if response.is_a?(Net::HTTPRedirection)
      location = URI.join(url, response.fetch("location")).to_s
      return fetch(location, redirects - 1)
    end
    raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    [ response, url ]
  end

  def add_frozen_raw_records(source_dir, staging, records)
    JSON.parse(source_dir.join("raw-manifest.json").read).each do |row|
      original = Pathname(row.fetch("path"))
      relative = original.relative_path_from(source_dir.join("raw"))
      copied = staging.join("raw", "frozen-2026-08-21", "raw", relative)
      records << raw_record_for_file(copied, "frozen-copy:#{row.fetch('url')}", row["content_type"])
    end
    audit_path = staging.join("raw", "first-nations-cross-roster-audit.json")
    records << raw_record_for_file(audit_path, "derived-from:first-nations/releases/2026-08-21/normalized-manifest.json", "application/json")
  end

  def raw_record(path, url, final_url, response)
    raw_record_for_file(path, url, response["content-type"], final_url: final_url, http_status: response.code.to_i)
  end

  def raw_record_for_file(path, url, content_type, final_url: nil, http_status: 200)
    {
      "url" => url, "final_url" => final_url || url, "path" => path.to_s,
      "retrieved_at" => RETRIEVED_AT, "http_status" => http_status,
      "content_type" => content_type.to_s.split(";").first, "byte_size" => path.size,
      "sha256" => Digest::SHA256.file(path).hexdigest, "cached_frozen_input" => true
    }
  end

  def summary(code, staging, release, failures)
    rows = release.fetch("municipalities")
    {
      "jurisdiction" => code, "status" => failures.empty? ? "complete" : "partial",
      "path" => staging.to_s.sub(/\.staging-\d+\z/, ""), "institutions" => rows.length,
      "active_institutions" => rows.count { |row| row["status"] == "active" },
      "historical_institutions" => rows.count { |row| row["status"] != "active" },
      "websites_verified" => rows.count { |row| row["website_url"] },
      "statscan_associations" => rows.sum { |row| Array(row["statcan_geographies"]).length },
      "documents" => rows.sum { |row| Array(row["documents"]).length },
      "failures" => failures.length, "gaps" => release.fetch("scrape_gaps").length,
      "classification_audit_path" => "classification-audit.json"
    }
  end

  def validate!(code, release_rows, normalized_rows)
    expected = code == "nt" ? 24 : 25
    raise "expected #{expected} #{code.upcase} institutions" unless release_rows.length == expected && normalized_rows.length == expected
    [ release_rows, normalized_rows ].each do |rows|
      ids = rows.map { |row| row.fetch("canonical_id") }
      raise "duplicate canonical IDs" unless ids.uniq.length == ids.length
      raise "missing CSD association" unless rows.all? { |row| Array(row["statcan_geographies"] || row["geography_associations"]).one? }
      raise "invalid canonical namespace" unless ids.all? { |id| id.start_with?("ca/#{code}/") }
    end
    if code == "nt"
      overlap = release_rows.map { |row| row.fetch("canonical_id") } & NT_DESIGNATED_AUTHORITIES.map { |row| row[3] }
      raise "ca/fn designated authority duplicated in ca/nt: #{overlap.join(', ')}" if overlap.any?
    end
  end

  def write_json(path, value)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(value) + "\n")
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end
end

options = {
  root: "/Volumes/floppy/york_factory/public_institutions/sources",
  release_date: NtNuLocalGovernmentAugmenter::RELEASE_DATE,
  download: true
}
OptionParser.new do |parser|
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--release-date DATE") { |value| options[:release_date] = value }
  parser.on("--no-download") { options[:download] = false }
end.parse!

NtNuLocalGovernmentAugmenter.new(**options).run if $PROGRAM_NAME == __FILE__
