#!/usr/bin/env ruby

require "cgi"
require "csv"
require "date"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "open3"
require "optparse"
require "pathname"
require "set"
require "time"
require "tmpdir"
require "uri"

class NationalLocalGovernmentScraper
  class ScrapeError < StandardError; end

  RELEASE_DATE = "2026-08-21"
  DEFAULT_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/sources")
  DEFAULT_STATCAN = Pathname(
    "/Volumes/floppy/york_factory/public_institutions/sources/ns-municipalities/" \
      "2026-08-19/sgc-cgt-2021-structure-eng.csv"
  )
  ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")
  USER_AGENT = "Build Canada public-institution source freezer/1.0"
  STATCAN_URL = "https://www.statcan.gc.ca/en/subjects/standard/sgc/2021/index"
  PROVINCE_CODES = {
    "nl" => "10", "pe" => "11", "nb" => "13", "qc" => "24", "on" => "35",
    "mb" => "46", "sk" => "47", "yt" => "60", "nt" => "61", "nu" => "62"
  }.freeze
  QUEBEC_NON_INSTITUTIONAL_LEGAL_FORMS = %w[
    reserve_indienne terre_de_la_categorie_i terre_de_la_categorie_ia
    terre_de_la_categorie_ia_n territoire_non_organise
  ].freeze
  JURISDICTIONS = PROVINCE_CODES.keys.freeze

  SK_CATEGORY_TYPES = {
    "City" => "city",
    "Town" => "town",
    "Village" => "village",
    "Resort Village" => "resort_village",
    "Rural Municipality" => "rural_municipality",
    "Northern Town" => "northern_town",
    "Northern Village" => "northern_village",
    "Northern Hamlet" => "northern_hamlet",
    "Northern Saskatchewan Administration District" => "territorial_administrative_area"
  }.freeze

  YUKON_SEED = {
    "city" => %w[Whitehorse Dawson],
    "town" => [ "Faro", "Watson Lake" ],
    "village" => [ "Carmacks", "Haines Junction", "Mayo", "Teslin" ],
    "local_advisory_council" => [ "Ibex Valley", "Marsh Lake", "Mount Lorne", "Tagish", "Carcross/South Klondike" ]
  }.freeze

  NUNAVUT_HAMLETS = [
    "Arctic Bay", "Arviat", "Baker Lake", "Cambridge Bay", "Chesterfield Inlet",
    "Clyde River", "Coral Harbour", "Gjoa Haven", "Grise Fiord", "Igloolik",
    "Kimmirut", "Kinngait", "Kugaaruk", "Kugluktuk", "Naujaat", "Pangnirtung",
    "Pond Inlet", "Qikiqtarjuaq", "Rankin Inlet", "Resolute", "Sanikiluaq",
    "Sanirajak", "Taloyoak", "Whale Cove"
  ].freeze

  NWT_BAND_SERVICE_AUTHORITIES = {
    "Behdzi Ahda First Nation" => "771",
    "Ka'a'gee Tu First Nation" => "768",
    "Kátł’odeeche First Nation" => "761",
    "Nahanni Butte Dene Band" => "766",
    "Pehdzeh Ki First Nation" => "756",
    "Sambaa K’e First Nation" => "767",
    "Tthets’éhk’édélı̨ First Nation" => "770",
    "Łutsel K’e Dene First Nation" => "764",
    "Yellowknives Dene First Nation (Dettah)" => "763"
  }.freeze

  PEI_SEED = {
    "city" => [ "Charlottetown", "Summerside" ],
    "town" => [
      "Alberton", "Borden-Carleton", "Cornwall", "Kensington", "O'Leary",
      "North Rustico", "Souris", "Stratford", "Three Rivers", "Tignish"
    ],
    "rural_municipality" => [
      "Abram-Village", "Alexandra", "Annandale-Little Pond-Howe Bay", "Bedeque and Area",
      "Belfast", "Brackley", "Breadalbane", "Central Kings", "Central Prince", "Clyde River",
      "Crapaud", "Eastern Kings", "Greenmount-Montrose", "Hampshire", "Hazelbrook", "Hunter River",
      "Kingston", "Kinkora", "Linkletter", "Lot 11 and Area", "Malpeque Bay", "Miltonvale Park",
      "Miminegash", "Miscouche", "Morell", "Mount Stewart", "Murray Harbour", "Murray River",
      "North Shore", "North Wiltshire", "Northport", "Resort", "Sherbrooke", "Souris West",
      "St. Felix", "St. Nicholas", "St. Peter's Bay", "Tignish Shore", "Tyne Valley", "Union Road",
      "Victoria", "Warren Grove", "Wellington", "West River", "York"
    ]
  }.freeze

  NL_INUIT_COMMUNITY_GOVERNMENTS = %w[Hopedale Makkovik Nain Postville Rigolet].to_set.freeze
  NL_CITIES = [ "Corner Brook", "Mount Pearl", "St. John's" ].to_set.freeze

  Context = Struct.new(
    :code, :output_dir, :raw_dir, :raw_manifest, :failures, :gaps, :mutex,
    keyword_init: true
  )

  attr_reader :summaries

  def initialize(root: DEFAULT_ROOT, release_date: RELEASE_DATE, retrieved_at: nil,
    statcan_path: DEFAULT_STATCAN, jurisdictions: JURISDICTIONS, threads: 12,
    download_assets: true)
    @root = Pathname(root)
    @release_date = Date.iso8601(release_date).iso8601
    @retrieved_at = Time.iso8601(retrieved_at || "#{@release_date}T12:00:00Z").utc
    @statcan_path = Pathname(statcan_path)
    @jurisdictions = jurisdictions.map(&:downcase)
    @threads = Integer(threads)
    @download_assets = download_assets
    @summaries = []
    unknown = @jurisdictions - JURISDICTIONS
    raise ArgumentError, "unknown jurisdictions: #{unknown.join(', ')}" if unknown.any?
  end

  def call
    FileUtils.mkdir_p(@root)
    @jurisdictions.each do |code|
      @summaries << process_jurisdiction(code)
    rescue StandardError => error
      @summaries << {
        "jurisdiction" => code,
        "status" => "failed",
        "error" => "#{error.class}: #{error.message}"
      }
    end
    write_json(@root.join("national-local-governments-#{@release_date}-summary.json"), {
      "release_date" => @release_date,
      "retrieved_at" => @retrieved_at.iso8601,
      "jurisdictions" => @summaries
    })
    @summaries
  end

  def parse_ontario_csv(bytes)
    rows = parse_utf8_csv(bytes)
    name_header = rows.headers.find { |header| header.to_s.match?(/Municipalit/i) }
    status_header = rows.headers.find { |header| header.to_s.match?(/status|statut/i) }
    area_header = rows.headers.find { |header| header.to_s.match?(/Geographic|géographique/i) }
    raise ScrapeError, "Ontario municipality CSV headers not recognized" unless name_header && status_header

    rows.map do |row|
      document = Nokogiri::HTML.fragment(row.fetch(name_header))
      anchor = document.at_css("a")
      name = (anchor&.[]("title") || anchor&.text || row.fetch(name_header)).strip
      {
        "name" => name,
        "website_url" => normalize_website(anchor&.[]("href")),
        "tier_label" => row.fetch(status_header).strip,
        "geographic_area" => area_header ? row[area_header]&.strip : nil
      }
    end
  end

  def parse_nb_population_table(text)
    types = [
      "Rural District / District rural",
      "Rural Community / Communauté rurale",
      "Regional Municipality / Municipalité régionale",
      "City / Cité", "Town / Ville", "Village"
    ]
    pattern = /\A\s*(\d+)\s+(.+?)\s{2,}(#{types.map { |value| Regexp.escape(value) }.join('|')})\s{2,}/
    lines = text.lines
    lines.each_with_index.filter_map do |line, index|
      match = line.match(pattern)
      next unless match

      name = match[2].strip
      name = lines[index - 1].to_s.strip if name.empty?
      { "row_number" => match[1], "display_name" => name, "type_label" => match[3] }
    end.uniq { |row| row.fetch("row_number") }
  end

  def parse_manitoba_directory(text)
    marker = "\fMANITOBA MUNICIPALITIES"
    start_at = text.index(marker)
    marker = "\nMANITOBA MUNICIPALITIES\n" unless start_at
    start_at ||= text.index(marker)
    marker = "MANITOBA MUNICIPALITIES\n" unless start_at
    start_at ||= text.index(marker)
    raise ScrapeError, "Manitoba municipality section not found" unless start_at
    start_at += marker.length
    finish_at = text.index("\nTHE CITY OF WINNIPEG\n", start_at) || text.length
    municipality_text = text[start_at...finish_at]

    heading = /^\f?(?<name>[^,\n]+?)(?:,\s*(?:\n\s*)?(?<type>RM|TOWN|CITY|VILLAGE|MUNICIPALITY|LGD|L\.G\.D\.)|\s+(?<bare_type>MUNICIPALITY))\s*$/
    matches = municipality_text.to_enum(:scan, heading).map { Regexp.last_match }
    rows = matches.each_with_index.map do |match, index|
      finish = matches[index + 1]&.begin(0) || municipality_text.length
      block = municipality_text[match.begin(0)...finish]
      website = block[/^Website\s*:?\s*(\S.*?)?\s*$/i, 1]
      municipal_number = block[/Municipal\s*#\s*:?\s*(\d+)/i, 1]
      {
        "name" => titleize_source_name(match[:name]),
        "type_label" => match[:type] || match[:bare_type],
        "website_url" => normalize_website(website),
        "municipal_number" => municipal_number
      }
    end
    rows.reject! { |row| row.fetch("name") == "Winnipeg" }
    rows << {
      "name" => "Winnipeg", "type_label" => "CHARTER CITY",
      "website_url" => "https://www.winnipeg.ca/", "municipal_number" => nil
    }
    rows.uniq { |row| [ row.fetch("name"), row.fetch("type_label") ] }
  end

  def parse_nl_directory(text)
    region_pattern = "Eastern|Western|Central|Labrador"
    text.lines.filter_map do |line|
      next if line.include?("Community Name") || line.include?("Official Community Name")
      match = line.match(/\A(?<name>\S.*?)(?:\s{2,}|\t+)(?<region>#{region_pattern})(?:\s{2,}|\t+)/)
      next unless match

      { "name" => match[:name].strip, "region" => match[:region] }
    end.uniq { |row| row.fetch("name") }
  end

  def match_statscan(institutions, code)
    candidates = statcan_candidates.fetch(code)
    by_name = candidates.group_by { |row| normalized_geography_name(row.fetch("name")) }
    institutions.each do |institution|
      # Regional bodies and Indigenous land corporations can share a name with a CSD without governing it.
      # Their geography requires an explicit structural or land-authority crosswalk.
      next if institution["tier"] == "regional"
      next if code == "qc" && institution.fetch("legal_form", "").include?("terre_de_la_categorie")

      source_name = institution["official_name_en"] || institution["official_name_fr"]
      key = normalized_geography_name(source_name)
      matches = by_name.fetch(key, [])
      next unless matches.one?

      candidate = matches.first
      institution["geography_associations"] << {
        "geography_id" => "ca/geography/csd-2021/#{candidate.fetch('uid')}",
        "code_system" => "statscan.sgc2021",
        "boundary_type" => "csd",
        "geo_uid" => candidate.fetch("uid"),
        "name" => candidate.fetch("name"),
        "role" => "governs",
        "match_method" => "exact_unique_normalized_name",
        "evidence_urls" => [ institution.fetch("source_url"), STATCAN_URL ],
        "notes" => "Association to frozen 2021 statistical geography; not an institution identifier."
      }
    end
  end

  private

  def process_jurisdiction(code)
    output_dir = @root.join("#{code}-local-governments", @release_date)
    context = Context.new(
      code: code,
      output_dir: output_dir,
      raw_dir: output_dir.join("raw"),
      raw_manifest: [],
      failures: [],
      gaps: [],
      mutex: Mutex.new
    )
    FileUtils.mkdir_p(context.raw_dir)
    archive_statcan(context)

    payload = send("scrape_#{code}", context)
    institutions = payload.fetch("institutions")
    institutions.each do |institution|
      institution["identifiers"] ||= []
      institution["geography_associations"] ||= []
      institution["relationships"] ||= []
      institution["documents"] ||= []
    end
    match_statscan(institutions, code)
    validate_payload!(institutions)

    normalized = {
      "schema_version" => "1.0",
      "release_date" => @release_date,
      "retrieved_at" => @retrieved_at.iso8601,
      "jurisdiction" => code,
      "source_authority" => payload.fetch("source_authority"),
      "institutions" => institutions.sort_by { |row| row.fetch("canonical_id") },
      "aggregate_documents" => payload.fetch("aggregate_documents", []),
      "gaps" => (context.gaps + payload.fetch("gaps", [])).uniq,
      "failures" => context.failures
    }
    write_json(output_dir.join("normalized-local-governments.json"), normalized)
    write_json(output_dir.join("release-manifest.json"), build_release_manifest(normalized, payload))
    write_json(output_dir.join("raw-manifest.json"), context.raw_manifest.sort_by { |row| row.fetch("path") })
    summary = {
      "jurisdiction" => code,
      "status" => context.failures.empty? ? "complete" : "partial",
      "path" => output_dir.to_s,
      "institutions" => institutions.length,
      "active_institutions" => institutions.count { |row| row.fetch("status") == "active" },
      "historical_institutions" => institutions.count { |row| row.fetch("status") == "historical" },
      "websites_verified" => institutions.count { |row| row["website_url"] },
      "statscan_associations" => institutions.sum { |row| row.fetch("geography_associations").length },
      "documents" => institutions.sum { |row| row.fetch("documents").length } + normalized.fetch("aggregate_documents").length,
      "failures" => context.failures.length,
      "gaps" => normalized.fetch("gaps").length
    }
    write_json(output_dir.join("scrape-summary.json"), summary)
    summary
  rescue StandardError => error
    context.failures << failure_record("jurisdiction", error)
    write_json(output_dir.join("raw-manifest.json"), context.raw_manifest) if context
    write_json(output_dir.join("scrape-summary.json"), {
      "jurisdiction" => code, "status" => "failed", "path" => output_dir.to_s,
      "error" => "#{error.class}: #{error.message}", "failures" => context.failures
    })
    raise
  end

  def scrape_on(context)
    package_url = "https://data.ontario.ca/api/3/action/package_show?id=municipalities"
    package = JSON.parse(archive_get(context, package_url, "ontario-municipalities-package.json"))
    resources = package.fetch("result").fetch("resources")
    en_resource = resources.find { |resource| resource["language"] == "english" && resource["format"] == "CSV" }
    fr_resource = resources.find { |resource| resource["language"] == "french" && resource["format"] == "CSV" }
    raise ScrapeError, "Ontario bilingual CSV resources missing" unless en_resource && fr_resource

    en_rows = parse_ontario_csv(archive_get(context, en_resource.fetch("url"), "municipalities-en.csv"))
    fr_rows = parse_ontario_csv(archive_get(context, fr_resource.fetch("url"), "municipalities-fr.csv"))
    french_by_website = fr_rows.to_h { |row| [ row.fetch("website_url"), row.fetch("name") ] }
    roster_url = "https://www.ontario.ca/page/list-ontario-municipalities"
    institutions = en_rows.map do |row|
      legal_form, base_name = ontario_legal_form(row.fetch("name"))
      tier = row.fetch("tier_label").downcase.tr(" ", "_").tr("-", "_")
      record = institution_record(
        code: "on", name_en: row.fetch("name"), name_fr: french_by_website[row.fetch("website_url")],
        legal_form: legal_form, tier: tier, kind: "municipal_government", source_url: roster_url,
        website_url: row.fetch("website_url"), website_source_url: en_resource.fetch("url"),
        slug_name: base_name
      )
      record["source_fields"] = { "municipal_status" => row.fetch("tier_label"), "geographic_area" => row["geographic_area"] }
      record
    end
    resolve_canonical_collisions!(institutions)
    by_core_name = institutions.group_by do |record|
      normalized_geography_name(record.fetch("official_name_en"))
    end
    institutions.each do |record|
      next unless record.fetch("tier") == "lower_tier"
      area = record.dig("source_fields", "geographic_area")
      parent = by_core_name.fetch(normalized_geography_name(area), []).find do |candidate|
        candidate.fetch("tier") == "upper_tier"
      end
      next unless parent
      record["relationships"] << relationship("administrative_parent", parent.fetch("canonical_id"), roster_url)
    end

    fir_url = "https://data.ontario.ca/api/3/action/package_show?id=financial-information-return-fir-for-municipalities"
    archive_optional(context, fir_url, "financial-information-return-package.json")
    {
      "source_authority" => "Ontario Ministry of Municipal Affairs and Housing",
      "institutions" => institutions,
      "aggregate_documents" => [ {
        "document_type" => "financial-data-return",
        "title" => "Ontario Financial Information Return (FIR)",
        "source_page_url" => "https://efis.fma.csc.gov.on.ca/fir/MultiYearReport/MYCIndex.html",
        "asset_path" => nil,
        "notes" => "Standardized annual return; not labelled or archived as an audited financial-statement PDF."
      } ],
      "gaps" => [ "Ontario audited municipal PDFs are decentralized and were not fetched by this roster adapter." ]
    }
  end

  def scrape_qc(context)
    roster_package_url = "https://www.donneesquebec.ca/recherche/api/3/action/package_show?id=repertoire-des-municipalites-du-quebec"
    archive_get(context, roster_package_url, "repertoire-package.json")
    mun_url = "https://donneesouvertes.affmunqc.net/repertoire/MUN.csv"
    mrc_url = "https://donneesouvertes.affmunqc.net/repertoire/MRC_CM_Arg.csv"
    mun_rows = parse_utf8_csv(archive_get(context, mun_url, "MUN.csv"))
    mrc_rows = parse_utf8_csv(archive_get(context, mrc_url, "MRC_CM_Arg.csv"))
    source_url = "https://www.donneesquebec.ca/recherche/fr/dataset/repertoire-des-municipalites-du-quebec"
    institutions = []
    regional_by_code = {}
    mrc_rows.each do |row|
      code = row.fetch("mrccod").strip
      designation = row.fetch("mrcdescdesi").strip
      record = institution_record(
        code: "qc", name_fr: row.fetch("mrcnom").strip, legal_form: snake_case(designation),
        tier: "regional", kind: "regional_government", source_url: source_url,
        website_url: normalize_website(row["mrcweb"]), website_source_url: mrc_url,
        namespace: "regional"
      )
      record["identifiers"] << identifier("qc.repertoire.mrc_cm_ar_code", code, source_url)
      record["source_fields"] = { "designation_code" => row["mrccodedesi"], "designation" => designation }
      institutions << record
      regional_by_code[code] = record
    end
    mun_rows.each do |row|
      code = row.fetch("mcode").strip
      designation = row.fetch("mdes").strip
      record = institution_record(
        code: "qc", name_fr: row.fetch("munnom").strip, legal_form: snake_case(designation),
        tier: "local", kind: "municipal_government", source_url: source_url,
        website_url: normalize_website(row["mweb"]), website_source_url: mun_url
      )
      record["identifiers"] << identifier("qc.code-geographique", code, source_url)
      record["source_fields"] = {
        "designation_code" => row["mcodedesi"], "designation" => designation,
        "mrc_display" => row["mrc"], "constitution_date" => row["mdatcons"]
      }
      mrc_numeric = row["mrc"].to_s[/\((\d{3})\)/, 1]
      parent = regional_by_code["AR#{mrc_numeric}"] if mrc_numeric
      record["relationships"] << relationship("administrative_parent", parent.fetch("canonical_id"), source_url) if parent
      institutions << record
    end
    excluded_geographies = institutions.select do |institution|
      QUEBEC_NON_INSTITUTIONAL_LEGAL_FORMS.include?(institution.fetch("legal_form"))
    end
    unless excluded_geographies.length == 158
      raise ScrapeError, "expected 158 Quebec non-institutional geography rows, found #{excluded_geographies.length}"
    end
    institutions -= excluded_geographies
    resolve_canonical_collisions!(institutions)

    finance_documents = scrape_quebec_financial_returns(context, institutions)
    {
      "source_authority" => "Ministère des Affaires municipales et de l'Habitation",
      "institutions" => institutions,
      "aggregate_documents" => finance_documents,
      "gaps" => [
        "Quebec municipal financial returns are aggregate data resources, not relabelled as original auditor-signed PDFs.",
        "MAMH excludes specified northern and Indigenous territories from this financial publication.",
        "Excluded 158 non-organizational MAMH geography rows from the institution roster: 30 Indian reserves, " \
          "23 Category I/IA/IA-N lands, and 105 unorganized territories. They require future geography ingestion; " \
          "actual Cree/Naskapi/northern-village corporations and regional governments remain included."
      ]
    }
  end

  def scrape_quebec_financial_returns(context, institutions)
    package_url = "https://www.donneesquebec.ca/recherche/api/3/action/package_show?id=rapport-financier-des-organismes-municipaux-et-autres-documents"
    package = JSON.parse(archive_get(context, package_url, "financial-returns/package.json"))
    resources = package.fetch("result").fetch("resources").select do |resource|
      name = resource.fetch("name", "")
      name.match?(/\ADonnées réelles 2025,/i) && resource.fetch("format", "").match?(/CSV|XLSX/i) &&
        !name.match?(/Description des postes/i)
    end
    resources.map do |resource|
      extension = resource.fetch("format").downcase
      relative = "financial-returns/2025/#{resource.fetch('id')}.#{extension}"
      bytes = archive_get(context, resource.fetch("url"), relative)
      {
        "document_type" => "financial-data-return",
        "title" => resource.fetch("name"),
        "fiscal_period_end" => "2025-12-31",
        "source_page_url" => "https://www.donneesquebec.ca/recherche/dataset/rapport-financier-des-organismes-municipaux-et-autres-documents",
        "download_url" => resource.fetch("url"),
        "asset_path" => context.raw_dir.join(relative).to_s,
        "sha256" => Digest::SHA256.hexdigest(bytes),
        "byte_size" => bytes.bytesize,
        "mime_type" => resource.fetch("mimetype", nil),
        "covered_institution_identifier_scheme" => "qc.code-geographique",
        "notes" => "Provincial municipal financial-report data return. Not asserted to be an original signed audited PDF."
      }
    rescue StandardError => error
      context.failures << failure_record(resource.fetch("url"), error)
      nil
    end.compact
  end

  def scrape_nb(context)
    pdf_url = "https://www.gnb.ca/content/dam/GNB3/org/elg-egl/doc/2025-local-government-and-rural-districts-statistic.pdf"
    regulation_url = "https://laws.gnb.ca/en/document/cr/2022-50/20221012"
    pdf = archive_get(context, pdf_url, "2025-local-government-and-rural-districts-statistics.pdf")
    archive_get(context, regulation_url, "regulation-2022-50.html")
    text = pdf_text(pdf, layout: true)
    rows = parse_nb_population_table(text)
    raise ScrapeError, "expected 89 New Brunswick entities, parsed #{rows.length}" unless rows.length == 89

    institutions = rows.map do |row|
      names = row.fetch("display_name").split(/\s+\/\s+/, 2)
      legal_form = {
        "City / Cité" => "city", "Town / Ville" => "town", "Village" => "village",
        "Rural Community / Communauté rurale" => "rural_community",
        "Regional Municipality / Municipalité régionale" => "regional_municipality",
        "Rural District / District rural" => "rural_district"
      }.fetch(row.fetch("type_label"))
      rural = legal_form == "rural_district"
      institution_record(
        code: "nb", name_en: names.first, name_fr: names[1] || names.first,
        legal_form: legal_form, tier: rural ? "province_administered_local_service_area" : "local",
        kind: rural ? "local_service_government" : "municipal_government",
        source_url: regulation_url, website_url: nil, website_source_url: nil,
        namespace: rural ? "rural-district" : nil,
        website_gap: "The bilingual legal/statistical roster does not supply a verified official website."
      )
    end
    {
      "source_authority" => "Government of New Brunswick",
      "institutions" => institutions,
      "gaps" => [ "Individual audited annual-report PDFs require per-local-government website crawling." ]
    }
  end

  def scrape_pe(context)
    roster_url = "https://www.princeedwardisland.ca/en/information/housing-land-and-communities/pei-municipalities"
    archive_optional(context, roster_url, "pei-municipalities.html")
    institutions = PEI_SEED.flat_map do |legal_form, names|
      names.map do |name|
        institution_record(
          code: "pe", name_en: name, legal_form: legal_form, tier: "local",
          kind: "municipal_government", source_url: roster_url,
          website_url: nil, website_source_url: nil,
          website_gap: "Official website is form-driven and could not be verified in this run."
        )
      end
    end
    finance_url = "https://www.princeedwardisland.ca/en/feature/municipal-financial-document-search"
    archive_optional(context, finance_url, "financial-statements/search.html")
    context.gaps << "PEI financial statement search was blocked by anti-bot controls; no PDFs were guessed or mislabelled."
    {
      "source_authority" => "Government of Prince Edward Island, Municipal Affairs",
      "institutions" => institutions,
      "gaps" => [ "The 57-name seed mirrors the dated official roster; the direct site response is preserved when accessible." ]
    }
  end

  def scrape_nl(context)
    towns_url = "https://www.gov.nl.ca/mca/files/Newfoundland-and-Labrador-Directory-of-Towns-ICGs-and-Cities-as-of-March-16-2026.pdf"
    lsd_url = "https://www.gov.nl.ca/mca/files/Newfoundland-and-Labrador-Directory-of-Local-Service-Districts-Information-as-of-March-16-2026.pdf"
    towns = parse_nl_directory(pdf_text(archive_get(context, towns_url, "towns-icgs-cities.pdf"), layout: true))
    lsds = parse_nl_directory(pdf_text(archive_get(context, lsd_url, "local-service-districts.pdf"), layout: true))
    institutions = towns.map do |row|
      name = row.fetch("name")
      legal_form = if NL_CITIES.include?(name)
        "city"
      elsif NL_INUIT_COMMUNITY_GOVERNMENTS.include?(name)
        "inuit_community_government"
      else
        "town"
      end
      institution_record(
        code: "nl", name_en: name, legal_form: legal_form, tier: "local",
        kind: legal_form == "inuit_community_government" ? "indigenous_government" : "municipal_government",
        source_url: towns_url, website_url: nil, website_source_url: nil,
        namespace: legal_form == "inuit_community_government" ? "inuit" : nil,
        website_gap: "The provincial contact PDF does not consistently provide official website URLs."
      ).merge("source_fields" => { "regional_office" => row.fetch("region") })
    end
    institutions.concat(lsds.map do |row|
      institution_record(
        code: "nl", name_en: row.fetch("name"), legal_form: "local_service_district",
        tier: "province_administered_local_service_area", kind: "local_service_government",
        source_url: lsd_url, website_url: nil, website_source_url: nil,
        namespace: "local-service-district",
        website_gap: "The provincial LSD directory does not provide verified official websites."
      ).merge("source_fields" => { "regional_office" => row.fetch("region") })
    end)
    {
      "source_authority" => "Newfoundland and Labrador Municipal and Community Affairs",
      "institutions" => institutions,
      "gaps" => [ "Municipal audited statements are decentralized; the roster PDFs are contact directories, not statement archives." ]
    }
  end

  def scrape_sk(context)
    directory_url = "https://www.saskatchewan.ca/government/municipal-administration/municipal-directory"
    landing = Nokogiri::HTML(archive_get(context, directory_url, "directory.html"))
    categories = landing.css("section.municipal-directory a[href*='?c=']").to_h do |anchor|
      [ anchor.text.strip, URI.join(directory_url, anchor["href"]).to_s ]
    end
    rows = []
    SK_CATEGORY_TYPES.each do |label, legal_form|
      url = categories[label]
      unless url
        context.failures << { "source" => directory_url, "error" => "missing Saskatchewan category #{label}" }
        next
      end
      encoded_url = encode_braces(url)
      page = Nokogiri::HTML(archive_get(context, encoded_url, "categories/#{legal_form}.html"))
      page.css("section.municipal-directory ul a[href*='?s=']").each do |anchor|
        rows << { "name" => anchor.text.strip, "legal_form" => legal_form, "profile_url" => encode_braces(URI.join(directory_url, anchor["href"]).to_s) }
      end
    end
    rows.uniq! { |row| row.fetch("profile_url") }
    institutions = parallel_map(rows) do |row|
      profile_id = URI.decode_www_form(URI(row.fetch("profile_url")).query).to_h.fetch("s").delete("{}")
      relative = "profiles/#{profile_id.downcase}.html"
      document = Nokogiri::HTML(archive_get(context, row.fetch("profile_url"), relative))
      table = document.at_css("div.row.general table")
      values = table ? table.css("tr").to_h { |tr| [ tr.at_css("th")&.text&.strip, tr.at_css("td")&.text&.strip ] } : {}
      website = normalize_website(values["URL"])
      kind = row.fetch("legal_form") == "territorial_administrative_area" ? "territorial_administrative_area" : "municipal_government"
      institution_record(
        code: "sk", name_en: row.fetch("name"), legal_form: row.fetch("legal_form"),
        tier: kind == "municipal_government" ? "local" : "territorial_administrative_area",
        kind: kind, source_url: directory_url, website_url: website,
        website_source_url: row.fetch("profile_url"),
        website_gap: website ? nil : "Official directory profile did not supply a website URL."
      ).merge("source_fields" => { "directory_profile_url" => row.fetch("profile_url") })
    rescue StandardError => error
      context.failures << failure_record(row.fetch("profile_url"), error)
      institution_record(
        code: "sk", name_en: row.fetch("name"), legal_form: row.fetch("legal_form"),
        tier: "local", kind: "municipal_government", source_url: directory_url,
        website_url: nil, website_source_url: nil,
        website_gap: "Profile fetch failed: #{error.message}"
      )
    end
    administrative_areas = institutions.select do |institution|
      institution.fetch("legal_form") == "territorial_administrative_area"
    end
    unless administrative_areas.map { |institution| institution.fetch("official_name_en") } ==
        [ "Northern Saskatchewan Administration District" ]
      raise ScrapeError, "expected the Northern Saskatchewan Administration District geography row"
    end
    institutions -= administrative_areas
    scrape_saskatchewan_statements(context, institutions) if @download_assets
    {
      "source_authority" => "Government of Saskatchewan",
      "institutions" => institutions,
      "gaps" => [
        ("Saskatchewan audited PDF download disabled by --skip-assets." unless @download_assets),
        "Northern Saskatchewan Administration District is a provincially administered territorial area, not a separate public institution; it is reserved for future geography ingestion."
      ].compact
    }
  end

  def scrape_saskatchewan_statements(context, institutions)
    root_url = "https://publications.saskatchewan.ca/api/v1/categories/6585"
    category = JSON.parse(archive_get(context, root_url, "financial-statements/category-6585.json"))
    by_name = institutions.group_by { |row| normalized_saskatchewan_name(row.fetch("official_name_en")) }
    formats = []
    category.fetch("childCategories").each do |child|
      year = child.fetch("nameEnglish")[/20\d{2}/]
      product_url = "https://publications.saskatchewan.ca/api/v1/categories/#{child.fetch('categoryId')}/products"
      products = JSON.parse(archive_get(context, product_url, "financial-statements/#{year}-products.json"))
      products.each do |product|
        product.fetch("productFormats", []).each do |format|
          next unless format["productFormatMediumType"] == "DIGITAL" && format["productFormatType"] == "PDF"
          formats << [ year, product, format ]
        end
      end
    end
    formats.each do |_year, product, format|
      name = format.fetch("description").sub(/\ANorthern (?:Hamlet|Town|Village) of /i, "")
      key = normalized_saskatchewan_name(name)
      next if by_name.fetch(key, []).one?

      product_id = product.fetch("productId")
      legal_form = saskatchewan_financial_product_legal_form(product.fetch("name"))
      historical = institution_record(
        code: "sk", name_en: name, legal_form: legal_form, tier: "local",
        kind: "municipal_government",
        source_url: "https://publications.saskatchewan.ca/#/products/#{product_id}",
        website_url: nil, website_source_url: nil,
        website_gap: "Historical municipality appears in the provincial audited-statement archive but not the current directory."
      )
      historical["status"] = "historical"
      historical["source_fields"] = {
        "historical_roster_basis" => "Saskatchewan audited financial statement product category",
        "current_directory_match" => false
      }
      semantic_match = institutions.select do |candidate|
        candidate.fetch("legal_form") == historical.fetch("legal_form") &&
          saskatchewan_name_stem(candidate.fetch("official_name_en")) ==
            saskatchewan_name_stem(historical.fetch("official_name_en"))
      end
      if semantic_match.one?
        # Provincial file descriptions occasionally contain a municipal-number typo
        # (for example Meota No. 68 instead of No. 468). The normalized base name and
        # legal form still identify the sole current institution, so retain its stable ID.
        by_name[key] = semantic_match
        next
      end
      institutions << historical
      by_name[key] = [ historical ]
    end
    resolve_canonical_collisions!(institutions)
    parallel_map(formats) do |year, product, format|
      name = format.fetch("description").sub(/\ANorthern (?:Hamlet|Town|Village) of /i, "")
      key = normalized_saskatchewan_name(name)
      matches = by_name.fetch(key, [])
      if matches.length != 1
        context.failures << {
          "source" => root_url, "error" => "could not uniquely link SK statement '#{name}' (#{year})",
          "candidate_count" => matches.length
        }
        next
      end
      institution = matches.first
      product_id = product.fetch("productId")
      format_id = format.fetch("productFormatId")
      download_url = "https://publications.saskatchewan.ca/api/v1/products/#{product_id}/formats/#{format_id}/download"
      bytes = archive_get(context, download_url, "financial-statements/#{year}/#{format_id}.pdf")
      raise ScrapeError, "download is not PDF" unless bytes.start_with?("%PDF-")
      document = {
        "document_type" => "audited-financial-statements",
        "title" => "#{institution.fetch('official_name_en')} #{year} Annual Financial Statements and Auditor's Report",
        "fiscal_period_end" => "#{year}-12-31",
        "source_page_url" => "https://publications.saskatchewan.ca/#/products/#{product_id}",
        "download_url" => download_url,
        "asset_path" => context.raw_dir.join("financial-statements/#{year}/#{format_id}.pdf").to_s,
        "sha256" => Digest::SHA256.hexdigest(bytes), "byte_size" => bytes.bytesize,
        "mime_type" => "application/pdf", "language" => format["language"] || "English",
        "source_product_id" => product_id, "source_format_id" => format_id,
        "shared_archive_path" => archive_shared_asset(
          bytes,
          source_path: context.raw_dir.join("financial-statements/#{year}/#{format_id}.pdf")
        )
      }
      context.mutex.synchronize { institution["documents"] << document }
    rescue StandardError => error
      context.failures << failure_record("SK statement #{format&.[]('productFormatId')}", error)
    end
  end

  def scrape_mb(context)
    url = "https://www.gov.mb.ca/mr/contactus/pubs/mod.pdf"
    rows = parse_manitoba_directory(pdf_text(archive_get(context, url, "municipal-officials-directory.pdf"), layout: false))
    raise ScrapeError, "expected 137 Manitoba municipalities, parsed #{rows.length}" unless rows.length == 137
    type_map = {
      "RM" => "rural_municipality", "TOWN" => "town", "CITY" => "city",
      "VILLAGE" => "village", "MUNICIPALITY" => "municipality",
      "LGD" => "local_government_district", "L.G.D." => "local_government_district",
      "CHARTER CITY" => "charter_city"
    }
    institutions = rows.map do |row|
      record = institution_record(
        code: "mb", name_en: row.fetch("name"), legal_form: type_map.fetch(row.fetch("type_label")),
        tier: "local", kind: "municipal_government", source_url: url,
        website_url: row.fetch("website_url"), website_source_url: url,
        website_gap: row.fetch("website_url") ? nil : "Official directory did not print a website."
      )
      if row["municipal_number"]
        record["identifiers"] << identifier("mb.municipal-number", row.fetch("municipal_number"), url)
      end
      record
    end
    resolve_canonical_collisions!(institutions)
    {
      "source_authority" => "Manitoba Municipal and Northern Relations",
      "institutions" => institutions,
      "gaps" => [ "Northern Affairs community governments are not part of the 137-municipality PDF and need a separate legal adapter." ]
    }
  end

  def scrape_yt(context)
    url = "https://yukon.ca/en/municipal-and-local-advisory-council-elections"
    archive_optional(context, url, "municipal-and-local-advisory-council-elections.html")
    institutions = YUKON_SEED.flat_map do |legal_form, names|
      names.map do |name|
        advisory = legal_form == "local_advisory_council"
        institution_record(
          code: "yt", name_en: advisory ? "#{name} Local Advisory Council" : name,
          legal_form: legal_form, tier: advisory ? "advisory" : "local",
          kind: advisory ? "advisory_body" : "municipal_government", source_url: url,
          website_url: nil, website_source_url: nil,
          namespace: advisory ? "local-advisory-council" : nil,
          website_gap: "Yukon source was Cloudflare-blocked in this run; no website was guessed."
        )
      end
    end
    {
      "source_authority" => "Government of Yukon",
      "institutions" => institutions,
      "gaps" => [ "Official Yukon HTML/PDF was blocked by Cloudflare; the reviewed dated legal roster seed was emitted with nil websites." ]
    }
  end

  def scrape_nt(context)
    list_url = "https://www.maca.gov.nt.ca/en/communitylist"
    links = (0..2).flat_map do |page_number|
      page_url = page_number.zero? ? list_url : "#{list_url}?page=#{page_number}"
      relative = page_number.zero? ? "communities.html" : "communities-page-#{page_number + 1}.html"
      page = Nokogiri::HTML(archive_get(context, page_url, relative))
      page.css(".views-field-title a[href*='/en/content/']").filter_map do |anchor|
        name = anchor.text.strip
        next if name.empty?
        [ name, URI.join(list_url, anchor["href"]).to_s ]
      end
    end.uniq { |name, _url| name }
    institutions = parallel_map(links) do |name, profile_url|
      relative = "profiles/#{slug(name)}.html"
      profile = Nokogiri::HTML(archive_get(context, profile_url, relative))
      text = profile.at_css("main")&.text.to_s.gsub(/\s+/, " ")
      official_name = clean_nwt_name(text[/Official Community Name:\s*(.*?)Community Status:/, 1] || name)
      status = clean_nwt_name(text[/Community Status:\s*(.*?)Incorporation Date:/, 1])
      legal_form = nwt_legal_form(official_name, status)
      website = profile.css("main a[href]").map { |a| a["href"] }.find do |href|
        href.to_s.match?(%r{\Ahttps?://}) && !href.include?("maca.gov.nt.ca")
      end
      kind = status.to_s.match?(/Designated Authority/i) ? "designated_authority" : "community_government"
      institution_record(
        code: "nt", name_en: official_name, legal_form: legal_form, tier: "local",
        kind: kind, source_url: profile_url, website_url: normalize_website(website),
        website_source_url: profile_url,
        website_gap: website ? nil : "MACA profile did not provide an external official website.",
        slug_name: nwt_semantic_name(official_name)
      ).merge("source_fields" => { "community_label" => name, "community_status" => status })
    rescue StandardError => error
      context.failures << failure_record(profile_url, error)
      institution_record(
        code: "nt", name_en: clean_nwt_name(name), legal_form: "unknown_community_government", tier: "local",
        kind: "community_government", source_url: list_url, website_url: nil,
        website_source_url: nil, website_gap: "Profile failed: #{error.message}",
        slug_name: nwt_semantic_name(name)
      )
    end
    raise ScrapeError, "expected 33 NWT communities, parsed #{institutions.length}" unless institutions.length == 33
    excluded = institutions.select do |institution|
      NWT_BAND_SERVICE_AUTHORITIES.key?(institution.fetch("official_name_en"))
    end
    unless excluded.length == NWT_BAND_SERVICE_AUTHORITIES.length
      raise ScrapeError, "expected 9 NWT band-council service authorities, found #{excluded.length}"
    end
    institutions -= excluded
    {
      "source_authority" => "Northwest Territories Municipal and Community Affairs",
      "institutions" => institutions,
      "gaps" => [
        "NWT actual community audited statements are decentralized.",
        "Nine MACA community entries are service-delivery roles of existing First Nation band councils and are not duplicated in ca/nt: " \
          "#{NWT_BAND_SERVICE_AUTHORITIES.map { |label, number| "#{label} (ISC #{number})" }.join('; ')}. " \
          "A future cross-roster enrichment should attach provides-services-for geography relationships to the ca/fn institutions."
      ]
    }
  end

  def scrape_nu(context)
    hamlets_url = "https://www.nunavutlegislation.ca/en/consolidated-law/hamlets-act-consolidation"
    cities_url = "https://www.nunavutlegislation.ca/en/consolidated-law/cities-towns-and-villages-act-consolidation"
    archive_optional(context, hamlets_url, "hamlets-act.html")
    archive_optional(context, cities_url, "cities-towns-villages-act.html")
    institutions = NUNAVUT_HAMLETS.map do |name|
      institution_record(
        code: "nu", name_en: name == "Resolute" ? "Hamlet of Resolute" : name,
        legal_form: "hamlet", tier: "local", kind: "municipal_government",
        source_url: hamlets_url, website_url: nil, website_source_url: nil,
        website_gap: "No current authoritative all-hamlet website directory was identified."
      )
    end
    institutions << institution_record(
      code: "nu", name_en: "Iqaluit", legal_form: "city", tier: "local",
      kind: "municipal_government", source_url: cities_url,
      website_url: "https://www.iqaluit.ca/", website_source_url: "https://www.iqaluit.ca/"
    )
    {
      "source_authority" => "Government of Nunavut / Nunavut Legislation",
      "institutions" => institutions,
      "gaps" => [ "The 25-name legal seed requires future order-level effective-date extraction; 24 websites remain unverified." ]
    }
  end

  def archive_statcan(context)
    raise ScrapeError, "StatsCan source missing: #{@statcan_path}" unless @statcan_path.file?
    target = context.raw_dir.join("statscan-sgc-2021-structure.csv")
    unless target.exist?
      FileUtils.mkdir_p(target.dirname)
      FileUtils.copy_file(@statcan_path, target)
    end
    context.raw_manifest << raw_record(
      target, "local-copy:#{@statcan_path}", 200, "text/csv", target.size
    )
  end

  def build_release_manifest(normalized, payload)
    province = province_metadata_for(normalized.fetch("jurisdiction"))
    municipalities = normalized.fetch("institutions").map do |institution|
      {
        "canonical_id" => institution.fetch("canonical_id"),
        "official_name_en" => institution["official_name_en"],
        "official_name_fr" => institution["official_name_fr"],
        "municipality_type" => institution.fetch("legal_form"),
        "tier" => institution.fetch("tier"),
        "institution_type" => manifest_institution_type(institution.fetch("institution_kind")),
        "government_level" => manifest_government_level(institution.fetch("institution_kind")),
        "status" => institution.fetch("status") == "historical" ? "inactive" : institution.fetch("status"),
        "website_url" => institution["website_url"],
        "website_source_url" => institution["website_source_url"] || institution.fetch("source_url"),
        "website_status" => institution.fetch("website_status"),
        "scrape_gaps" => [ institution["website_gap"] ].compact,
        "source_languages" => [ ("en" if institution["official_name_en"]), ("fr" if institution["official_name_fr"]) ].compact,
        "identifiers" => institution.fetch("identifiers").map do |identifier|
          identifier.slice("scheme", "value").merge("preferred" => identifier.fetch("preferred", false))
        end,
        "statcan_geographies" => institution.fetch("geography_associations").map do |geography|
          {
            "uid" => geography.fetch("geo_uid"),
            "name" => geography.fetch("name"),
            "boundary_type" => geography.fetch("boundary_type"),
            "vintage" => 2021,
            "province_code" => province.fetch("statcan_code"),
            "role" => geography.fetch("role"),
            "match_method" => geography.fetch("match_method"),
            "evidence_urls" => geography.fetch("evidence_urls")
          }
        end,
        "documents" => institution.fetch("documents").map do |document|
          manifest_document(institution.fetch("canonical_id"), document)
        end
      }
    end
    relationships = normalized.fetch("institutions").flat_map do |institution|
      institution.fetch("relationships").map do |relationship|
        {
          "source_id" => institution.fetch("canonical_id"),
          "target_id" => relationship.fetch("target_canonical_id"),
          "relationship_type" => relationship.fetch("relationship_type"),
          "primary" => relationship.fetch("relationship_type") == "administrative_parent",
          "notes" => "Source: #{relationship.fetch('source_url')}"
        }
      end
    end
    {
      "release_version" => @release_date,
      "effective_on" => @release_date,
      "schema_version" => "1.0",
      "published_at" => @retrieved_at.iso8601,
      "source_retrieved_at" => @retrieved_at.iso8601,
      "geography_vintage" => 2021,
      "geography_source_url" => STATCAN_URL,
      "attribution" => "Official jurisdiction rosters and Statistics Canada SGC 2021; see frozen raw-manifest.json and per-row sources.",
      "include_jurisdiction_institution" => true,
      "province" => province,
      "roster_source_publisher" => normalized.fetch("source_authority"),
      "roster_source_title" => "Official #{province.fetch('name_en')} local-government roster snapshot",
      "roster_source_url" => primary_roster_url(normalized.fetch("jurisdiction")),
      "municipalities" => municipalities,
      "relationships" => relationships,
      "coverage" => release_coverage(normalized, province),
      "scrape_gaps" => normalized.fetch("gaps"),
      "scrape_failures" => normalized.fetch("failures"),
      "aggregate_documents" => normalized.fetch("aggregate_documents"),
      "raw_manifest_path" => normalized.fetch("jurisdiction") + "-local-governments/#{@release_date}/raw-manifest.json"
    }
  end

  def release_coverage(normalized, province)
    code = normalized.fetch("jurisdiction")
    institutions = normalized.fetch("institutions")
    institution_count = institutions.length
    active_count = institutions.count { |institution| institution.fetch("status", "active") == "active" }
    historical_count = institution_count - active_count
    website_count = institutions.count { |institution| institution["website_url"] }
    geography_count = institutions.count { |institution| institution.fetch("geography_associations").any? }
    relationship_count = institutions.sum { |institution| institution.fetch("relationships").length }
    statement_count = institutions.sum do |institution|
      institution.fetch("documents").count { |document| document["document_type"] == "audited-financial-statements" }
    end
    scope_id = "ca/#{code}"
    roster_url = primary_roster_url(code)

    rows = [
      coverage_row(
        scope_id, "institutions", institution_coverage_status(code),
        institution_coverage_notes(code, institution_count, active_count, historical_count), roster_url
      ),
      coverage_row(
        scope_id, "websites", website_count == institution_count ? "complete" : "partial",
        "#{website_count} of #{institution_count} institutions have an upstream-verified official website URL.", roster_url
      ),
      coverage_row(
        scope_id, "geographies",
        geography_count.zero? ? "not-found" : (geography_count == institution_count ? "complete" : "partial"),
        geography_coverage_notes(code, geography_count, institution_count),
        STATCAN_URL
      ),
      coverage_row(
        scope_id, "relationships", relationship_count.positive? ? "partial" : "not-searched",
        relationship_count.positive? ? "#{relationship_count} explicit upstream-supported administrative relationships were emitted." : "No jurisdiction-wide relationship extraction was performed beyond relationships directly exposed by the roster adapter.",
        roster_url
      ),
      coverage_row(
        scope_id, "financial-statements", financial_statement_coverage_status(code, statement_count),
        financial_statement_coverage_notes(code, statement_count), financial_statement_source_url(code)
      ),
      coverage_row(
        scope_id, "annual-reports", "not-searched",
        "Annual reports were outside this shallow roster release and were not searched jurisdiction-wide.", roster_url
      )
    ]

    if %w[on qc].include?(code)
      resource_count = normalized.fetch("aggregate_documents").count do |document|
        document["document_type"] == "financial-data-return"
      end
      rows << coverage_row(
        scope_id, "financial-data-return", "partial",
        code == "qc" ? "#{resource_count} current 2025 MAMH aggregate financial-data-return resources are frozen in the source archive but are not emitted as institution document rows; they are not auditor-signed statements." : "The Ontario FIR index is identified, but its municipal return files were not archived in this shallow release.",
        code == "qc" ? "https://www.donneesquebec.ca/recherche/fr/dataset/rapports-financiers-des-municipalites" : "https://efis.fma.csc.gov.on.ca/fir/MultiYearReport/MYCIndex.html"
      )
    end

    document_status, document_notes = document_asset_coverage(code, statement_count, normalized)
    rows << coverage_row(scope_id, "document-assets", document_status, document_notes, financial_statement_source_url(code))
    rows
  end

  def coverage_row(scope_id, subject, status, notes, source_url = nil)
    { "scope_id" => scope_id, "subject" => subject, "status" => status, "notes" => notes }.tap do |row|
      row["source_url"] = source_url if source_url
    end
  end

  def institution_coverage_status(code)
    return "partial" if %w[pe mb yt nt nu].include?(code)
    "complete"
  end

  def institution_coverage_notes(code, institution_count, active_count, historical_count)
    if code == "qc"
      return "#{institution_count} public organizations emitted; 158 MAMH reserve, Category I land, and unorganized-territory rows were excluded as geographies rather than institutions."
    end
    return "#{institution_count} institutions emitted from the stated jurisdiction roster scope." if historical_count.zero?
    "#{institution_count} institutions emitted: #{active_count} current roster institutions and #{historical_count} historical institutions evidenced by the statement archive."
  end

  def geography_coverage_notes(code, geography_count, institution_count)
    note = "#{geography_count} of #{institution_count} institutions have an exact unique-name Statistics Canada SGC 2021 association."
    return note unless code == "qc"
    "#{note} The 158 non-organizational MAMH geography rows are excluded pending dedicated geography ingestion."
  end

  def clean_nwt_name(value)
    value.to_s.gsub(/\A[[:space:]\u00a0]+|[[:space:]\u00a0]+\z/, "")
  end

  def nwt_semantic_name(value)
    cleaned = clean_nwt_name(value)
    return "Deline Gotine Government" if cleaned == "Délı̨nę Got’ı̨nę Government"

    cleaned.sub(
      /\A(?:City|Town|Village|Hamlet|Charter Community|Community Government)\s+of\s+/i, ""
    )
  end

  def nwt_legal_form(official_name, status)
    return "tlicho_community_government" if official_name.match?(/\ACommunity Government of (?:Behchokǫ̀|Gamètì|Wekweètì|Whatì)\z/i)
    return "self_government_community_government" if official_name.match?(/\ADélı̨nę Got’ı̨nę Government\z/i)
    return "charter_community" if official_name.match?(/\ACharter Community of /i)
    return "city" if official_name.match?(/\ACity of /i)
    return "town" if official_name.match?(/\ATown of /i)
    return "village" if official_name.match?(/\AVillage of /i)
    return "hamlet" if official_name.match?(/\AHamlet of /i)
    snake_case(status || "community_government")
  end

  def financial_statement_coverage_status(code, statement_count)
    return statement_count.positive? ? "partial" : "failed" if code == "sk"
    return "unavailable" if code == "pe"
    "not-searched"
  end

  def financial_statement_coverage_notes(code, statement_count)
    return "#{statement_count} Saskatchewan audited statement PDFs from the provincial 2022-2024 archive were linked to current or explicit historical institutions." if code == "sk"
    return "The provincial municipal financial-document search was blocked by anti-bot controls; no PDF URLs were guessed." if code == "pe"
    return "Audited financial statements were not searched jurisdiction-wide in this shallow roster release." unless code == "qc"
    "Quebec financial-data-return files were archived separately and were not relabelled as auditor-signed financial statements."
  end

  def financial_statement_source_url(code)
    return "https://publications.saskatchewan.ca/#/categories/6585" if code == "sk"
    return "https://www.princeedwardisland.ca/en/feature/municipal-financial-document-search" if code == "pe"
    primary_roster_url(code)
  end

  def document_asset_coverage(code, statement_count, normalized)
    if code == "sk"
      return [ statement_count.positive? ? "complete" : "failed", "All #{statement_count} emitted statement records have frozen, content-addressed PDF assets." ]
    end
    if code == "qc"
      count = normalized.fetch("aggregate_documents").count { |document| document["asset_path"] }
      return [ "partial", "#{count} Quebec aggregate financial-data-return resources have frozen source assets, but no institution document assets are emitted by this manifest." ]
    end
    return [ "unavailable", "The upstream PEI document search was blocked; no assets could be identified safely." ] if code == "pe"
    [ "not-searched", "Document assets were not searched jurisdiction-wide in this shallow roster release." ]
  end

  def manifest_document(institution_id, document)
    year = document.fetch("fiscal_period_end")[/\A(\d{4})/, 1]
    archive_path = document.fetch("shared_archive_path")
    {
      "canonical_id" => "#{institution_id}/documents/financial-statements/#{year}/consolidated",
      "document_type" => "financial-statements",
      "document_variant" => "consolidated",
      "title" => document.fetch("title"),
      "fiscal_period_start" => "#{year}-01-01",
      "fiscal_period_end" => document.fetch("fiscal_period_end"),
      "published_on" => nil,
      "source_page_url" => document.fetch("source_page_url"),
      "download_url" => document.fetch("download_url"),
      "notes" => "Official Saskatchewan audited financial statements and auditor's report.",
      "assets" => [ {
        "content_sha256" => document.fetch("sha256"),
        "asset_role" => "final",
        "preferred" => true,
        "download_url" => document.fetch("download_url"),
        "retrieved_at" => @retrieved_at.iso8601,
        "archive_path" => archive_path,
        "mime_type" => "application/pdf",
        "byte_size" => document.fetch("byte_size"),
        "rights_status" => "metadata_only"
      } ]
    }
  end

  def archive_shared_asset(bytes, source_path: nil)
    sha256 = Digest::SHA256.hexdigest(bytes)
    relative = Pathname("sha256").join(sha256[0, 2], "#{sha256}.pdf")
    target = ASSET_ROOT.join(relative)
    unless target.file?
      FileUtils.mkdir_p(target.dirname)
      if source_path && Pathname(source_path).file?
        begin
          File.link(source_path, target)
        rescue Errno::EEXIST
          # Another worker archived identical bytes.
        end
      else
        temporary = target.dirname.join(".#{target.basename}.#{Process.pid}.#{Thread.current.object_id}.tmp")
        temporary.binwrite(bytes)
        FileUtils.mv(temporary, target)
      end
    end
    raise ScrapeError, "shared asset hash mismatch: #{target}" unless Digest::SHA256.file(target).hexdigest == sha256
    relative.to_s
  ensure
    temporary&.delete if defined?(temporary) && temporary&.exist?
  end

  def province_metadata_for(code)
    {
      "nl" => [ "10", "Newfoundland and Labrador", "Terre-Neuve-et-Labrador", "Government of Newfoundland and Labrador", "Gouvernement de Terre-Neuve-et-Labrador", "https://www.gov.nl.ca/", [ "en" ], "Open Government Licence - Newfoundland and Labrador" ],
      "pe" => [ "11", "Prince Edward Island", "Île-du-Prince-Édouard", "Government of Prince Edward Island", "Gouvernement de l'Île-du-Prince-Édouard", "https://www.princeedwardisland.ca/", [ "en" ], "Open Government Licence - Prince Edward Island" ],
      "nb" => [ "13", "New Brunswick", "Nouveau-Brunswick", "Government of New Brunswick", "Gouvernement du Nouveau-Brunswick", "https://www.gnb.ca/", [ "en", "fr" ], "Open Government Licence - New Brunswick" ],
      "qc" => [ "24", "Quebec", "Québec", "Government of Quebec", "Gouvernement du Québec", "https://www.quebec.ca/", [ "fr" ], "CC BY 4.0" ],
      "on" => [ "35", "Ontario", "Ontario", "Government of Ontario", "Gouvernement de l'Ontario", "https://www.ontario.ca/", [ "en", "fr" ], "Open Government Licence - Ontario" ],
      "mb" => [ "46", "Manitoba", "Manitoba", "Government of Manitoba", "Gouvernement du Manitoba", "https://www.gov.mb.ca/", [ "en" ], "Open Government Licence - Manitoba" ],
      "sk" => [ "47", "Saskatchewan", "Saskatchewan", "Government of Saskatchewan", nil, "https://www.saskatchewan.ca/", [ "en" ], "Open Government Licence - Saskatchewan" ],
      "yt" => [ "60", "Yukon", "Yukon", "Government of Yukon", "Gouvernement du Yukon", "https://yukon.ca/", [ "en" ], "Open Government Licence - Yukon" ],
      "nt" => [ "61", "Northwest Territories", "Territoires du Nord-Ouest", "Government of the Northwest Territories", "Gouvernement des Territoires du Nord-Ouest", "https://www.gov.nt.ca/", [ "en" ], "Open Government Licence - Northwest Territories" ],
      "nu" => [ "62", "Nunavut", "Nunavut", "Government of Nunavut", "Gouvernement du Nunavut", "https://www.gov.nu.ca/", [ "en" ], "Open Government Licence - Nunavut" ]
    }.fetch(code).then do |values|
      statcan_code, name_en, name_fr, government_en, government_fr, website, languages, license = values
      {
        "code" => code, "statcan_code" => statcan_code, "name_en" => name_en, "name_fr" => name_fr,
        "government_name_en" => government_en, "government_name_fr" => government_fr,
        "website_url" => website, "source_languages" => languages, "source_license" => license
      }
    end
  end

  def primary_roster_url(code)
    {
      "nl" => "https://www.gov.nl.ca/mca/municipal-directory/",
      "pe" => "https://www.princeedwardisland.ca/en/information/housing-land-and-communities/pei-municipalities",
      "nb" => "https://laws.gnb.ca/en/document/cr/2022-50/20221012",
      "qc" => "https://www.donneesquebec.ca/recherche/fr/dataset/repertoire-des-municipalites-du-quebec",
      "on" => "https://www.ontario.ca/page/list-ontario-municipalities",
      "mb" => "https://www.gov.mb.ca/mr/contactus/pubs/mod.pdf",
      "sk" => "https://www.saskatchewan.ca/government/municipal-administration/municipal-directory",
      "yt" => "https://yukon.ca/en/municipal-and-local-advisory-council-elections",
      "nt" => "https://www.maca.gov.nt.ca/en/communitylist",
      "nu" => "https://www.nunavutlegislation.ca/en/consolidated-law/hamlets-act-consolidation"
    }.fetch(code)
  end

  def manifest_institution_type(kind)
    return "board" if kind == "advisory_body"
    "government"
  end

  def manifest_government_level(kind)
    return "regional" if kind == "regional_government"
    return "inuit" if kind == "indigenous_government"
    return "other" if %w[advisory_body local_service_government territorial_administrative_area designated_authority].include?(kind)
    "municipal"
  end

  def statcan_candidates
    @statcan_candidates ||= begin
      rows = CSV.read(@statcan_path, headers: true, encoding: "ISO-8859-1:UTF-8")
      PROVINCE_CODES.to_h do |code, prefix|
        candidates = rows.filter_map do |row|
          next unless row["Level"] == "4" && row.fetch("Code").start_with?(prefix)
          { "uid" => row.fetch("Code"), "name" => row.fetch("Class title") }
        end
        [ code, candidates ]
      end
    end
  end

  def archive_get(context, url, relative_path)
    target = context.raw_dir.join(relative_path)
    if target.file?
      bytes = target.binread
      blocked = blocked_response?(bytes)
      failure_status = cached_failure_status(bytes)
      context.mutex.synchronize do
        context.raw_manifest << raw_record(
          target, url, blocked ? 403 : (failure_status || 200), mime_from_path(target), bytes.bytesize, cached: true
        )
      end
      raise ScrapeError, "cached anti-bot response for #{url}" if blocked
      raise ScrapeError, "cached HTTP #{failure_status} response for #{url}" if failure_status
      return bytes
    end

    response, final_url = http_get(url)
    bytes = response.body.to_s.b
    FileUtils.mkdir_p(target.dirname)
    temporary = target.dirname.join(".#{target.basename}.#{Process.pid}.#{Thread.current.object_id}.tmp")
    temporary.binwrite(bytes)
    FileUtils.mv(temporary, target)
    context.mutex.synchronize do
      context.raw_manifest << raw_record(
        target, url, response.code.to_i, response["content-type"], bytes.bytesize,
        final_url: final_url
      )
    end
    raise ScrapeError, "HTTP #{response.code} for #{url}" unless response.is_a?(Net::HTTPSuccess)
    raise ScrapeError, "anti-bot response for #{url}" if blocked_response?(bytes)
    bytes
  ensure
    temporary&.delete if defined?(temporary) && temporary&.exist?
  end

  def blocked_response?(bytes)
    sample = bytes.byteslice(0, 256_000).to_s
    sample.include?("Incident ID:") || sample.include?("Just a moment...") ||
      sample.include?("_cf_chl_opt") || sample.include?("cf-mitigated")
  end

  def cached_failure_status(bytes)
    return unless bytes.start_with?("{")
    payload = JSON.parse(bytes)
    404 if payload.is_a?(Hash) && payload["error"].to_s.match?(/not find|not found/i)
  rescue JSON::ParserError
    nil
  end

  def archive_optional(context, url, relative_path)
    archive_get(context, url, relative_path)
  rescue StandardError => error
    context.failures << failure_record(url, error)
    nil
  end

  def http_get(url, redirects: 8)
    raise ScrapeError, "too many redirects for #{url}" if redirects.zero?
    uri = URI(URI::DEFAULT_PARSER.escape(url))
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "*/*"
    response = Net::HTTP.start(
      uri.hostname, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: 20, read_timeout: 120
    ) { |http| http.request(request) }
    if response.is_a?(Net::HTTPRedirection)
      next_url = URI.join(url, response.fetch("location")).to_s
      return http_get(next_url, redirects: redirects - 1)
    end
    if response.code.to_i == 429 || response.code.to_i >= 500
      sleep 1
      return http_get(url, redirects: redirects - 1)
    end
    [ response, url ]
  end

  def institution_record(code:, legal_form:, tier:, kind:, source_url:, name_en: nil, name_fr: nil,
    website_url: nil, website_source_url: nil, website_gap: nil, namespace: nil, slug_name: nil)
    name = slug_name || name_en || name_fr
    path = [ "ca", code, namespace, slug(name) ].compact.join("/")
    {
      "canonical_id" => path,
      "official_name_en" => name_en,
      "official_name_fr" => name_fr,
      "legal_form" => legal_form,
      "tier" => tier,
      "institution_kind" => kind,
      "website_url" => website_url,
      "website_status" => website_url ? "verified_upstream" : "gap",
      "website_source_url" => website_source_url,
      "website_gap" => website_url ? nil : (website_gap || "No verified official website in authoritative source."),
      "status" => "active",
      "source_url" => source_url,
      "identifiers" => [],
      "geography_associations" => [],
      "relationships" => [],
      "documents" => []
    }
  end

  def identifier(scheme, value, source_url)
    { "scheme" => scheme, "value" => value, "source_url" => source_url }
  end

  def relationship(type, target, source_url)
    { "relationship_type" => type, "target_canonical_id" => target, "source_url" => source_url }
  end

  def validate_payload!(institutions)
    ids = institutions.map { |row| row.fetch("canonical_id") }
    duplicates = ids.tally.select { |_id, count| count > 1 }
    raise ScrapeError, "duplicate canonical IDs: #{duplicates.keys.join(', ')}" if duplicates.any?

    institutions.each do |row|
      raise ScrapeError, "missing legal form: #{row.fetch('canonical_id')}" if row["legal_form"].to_s.empty?
      raise ScrapeError, "missing tier: #{row.fetch('canonical_id')}" if row["tier"].to_s.empty?
      if row["website_url"].nil? && row["website_gap"].to_s.empty?
        raise ScrapeError, "website gap is not explicit: #{row.fetch('canonical_id')}"
      end
      if row.fetch("identifiers").any? { |identifier| identifier.fetch("scheme").start_with?("statscan") }
        raise ScrapeError, "StatsCan value incorrectly emitted as institution identifier: #{row.fetch('canonical_id')}"
      end
      row.fetch("documents").each do |document|
        if document.fetch("document_type") == "audited-financial-statements"
          raise ScrapeError, "audited statement is not PDF: #{document['download_url']}" unless document["mime_type"] == "application/pdf"
        end
      end
    end
  end

  def ontario_legal_form(name)
    suffixes = {
      /, City of\z/i => "city", /, Town of\z/i => "town", /, Township of\z/i => "township",
      /, Village of\z/i => "village", /, Municipality of\z/i => "municipality",
      /, County of\z/i => "county", /, Regional Municipality of\z/i => "regional_municipality",
      /, District Municipality of\z/i => "district_municipality",
      /, United Townships of\z/i => "united_townships"
    }
    pattern, legal_form = suffixes.find { |candidate, _value| name.match?(candidate) }
    [ legal_form || "municipality", pattern ? name.sub(pattern, "") : name ]
  end

  def normalized_geography_name(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase
      .sub(/\A(?:city|town|village|hamlet|municipality|rural municipality|rm|northern town|northern village|northern hamlet)\s+of\s+/, "")
      .sub(/,\s*(?:city|town|village|township|municipality|county|regional municipality|district municipality|united townships)\s+of\z/, "")
      .sub(/\Arm\s+of\s+/, "")
      .sub(/,?\s+no\.?\s*\d+\z/, "")
      .gsub("&", " and ")
      .gsub(/[^a-z0-9]+/, " ").strip.gsub(/\s+/, " ")
  end

  def normalized_saskatchewan_name(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase
      .sub(/\Arm\s*of\s+/, "")
      .sub(/\A(?:northern hamlet|northern town|northern village)\s+of\s+/, "")
      .sub(/,\s*rural municipality\s+no\.?\s*/, " no ")
      .gsub(/[^a-z0-9]+/, " ").strip.gsub(/\s+/, " ")
  end

  def saskatchewan_name_stem(value)
    normalized = normalized_saskatchewan_name(value)
    number_suffix = if value.to_s.match?(/\A\s*(?:rm|rural municipality)\s+of\b/i)
      /\s+(?:no\s+)?\d+\z/
    else
      /\s+no\s+\d+\z/
    end
    normalized.sub(number_suffix, "")
  end

  def saskatchewan_financial_product_legal_form(product_name)
    case product_name
    when /Resort Village/i then "resort_village"
    when /Rural Municipality/i then "rural_municipality"
    when /Northern Municipality/i then "northern_municipality"
    when /City/i then "city"
    when /Town/i then "town"
    when /Village/i then "village"
    else "municipality"
    end
  end

  def resolve_canonical_collisions!(institutions)
    institutions.group_by { |row| row.fetch("canonical_id") }.each_value do |rows|
      next if rows.one?
      rows.each do |row|
        row["canonical_id"] = "#{row.fetch('canonical_id')}-#{row.fetch('legal_form').tr('_', '-')}"
      end
      rows.group_by { |row| row.fetch("canonical_id") }.each_value do |remaining|
        next if remaining.one?
        remaining.each do |row|
          discriminator = row.fetch("identifiers").first&.fetch("value", nil)
          raise ScrapeError, "unresolvable semantic collision for #{row.fetch('canonical_id')}" unless discriminator
          row["canonical_id"] = "#{row.fetch('canonical_id')}-#{slug(discriminator)}"
        end
      end
    end
  end

  def slug(value)
    normalized_geography_name(value).tr(" ", "-").sub(/\A-+|-+\z/, "")
  end

  def snake_case(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_+|_+\z/, "")
  end

  def titleize_source_name(value)
    small = %w[of the and du de la des]
    value.downcase.split.map.with_index do |part, index|
      index.positive? && small.include?(part) ? part : part.split("-").map(&:capitalize).join("-")
    end.join(" ")
  end

  def normalize_website(value)
    value = value.to_s.strip
    return nil if value.empty? || value == ":" || value.match?(/\A(?:n\/a|none)\z/i)
    value = "https://#{value}" unless value.match?(%r{\Ahttps?://}i)
    uri = URI(value)
    return nil unless uri.host
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def parse_utf8_csv(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "") unless text.valid_encoding?
    text = text.sub(/\A\uFEFF/, "")
    CSV.parse(text, headers: true)
  end

  def encode_braces(url)
    url.gsub("{", "%7B").gsub("}", "%7D")
  end

  def pdf_text(bytes, layout: false)
    args = [ "pdftotext" ]
    args << "-layout" if layout
    args.concat([ "-", "-" ])
    text, status = Open3.capture2(*args, stdin_data: bytes)
    raise ScrapeError, "pdftotext failed" unless status.success?
    text
  end

  def parallel_map(items)
    queue = Queue.new
    items.each_with_index { |item, index| queue << [ index, item ] }
    results = Array.new(items.length)
    workers = [ @threads, items.length ].min.times.map do
      Thread.new do
        loop do
          index, item = queue.pop(true)
          results[index] = yield(item)
        rescue ThreadError
          break
        end
      end
    end
    workers.each(&:join)
    results.compact
  end

  def raw_record(path, url, status, content_type, byte_size, final_url: nil, cached: false)
    {
      "url" => url,
      "final_url" => final_url || url,
      "path" => path.to_s,
      "retrieved_at" => @retrieved_at.iso8601,
      "http_status" => status,
      "content_type" => content_type,
      "byte_size" => byte_size,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "cached_frozen_input" => cached
    }
  end

  def mime_from_path(path)
    { ".json" => "application/json", ".csv" => "text/csv", ".html" => "text/html", ".pdf" => "application/pdf", ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }[path.extname.downcase] || "application/octet-stream"
  end

  def failure_record(source, error)
    { "source" => source, "error" => "#{error.class}: #{error.message}" }
  end

  def write_json(path, value)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(value) + "\n")
  end
end
if $PROGRAM_NAME == __FILE__
  options = {
    root: NationalLocalGovernmentScraper::DEFAULT_ROOT,
    release_date: NationalLocalGovernmentScraper::RELEASE_DATE,
    statcan_path: NationalLocalGovernmentScraper::DEFAULT_STATCAN,
    jurisdictions: NationalLocalGovernmentScraper::JURISDICTIONS,
    threads: 12,
    download_assets: true
  }
  parser = OptionParser.new do |opts|
    opts.banner = "usage: #{$PROGRAM_NAME} [options]"
    opts.on("--root PATH", "Source output root") { |value| options[:root] = Pathname(value) }
    opts.on("--release-date DATE", "Frozen effective date") { |value| options[:release_date] = value }
    opts.on("--retrieved-at TIME", "Frozen retrieval timestamp") { |value| options[:retrieved_at] = value }
    opts.on("--statcan PATH", "SGC 2021 structure CSV") { |value| options[:statcan_path] = Pathname(value) }
    opts.on("--jurisdictions LIST", "Comma-separated codes") { |value| options[:jurisdictions] = value.split(",") }
    opts.on("--threads N", Integer, "Network workers") { |value| options[:threads] = value }
    opts.on("--skip-assets", "Do not download centralized PDF assets") { options[:download_assets] = false }
  end
  parser.parse!
  scraper = NationalLocalGovernmentScraper.new(**options)
  summaries = scraper.call
  puts JSON.pretty_generate(summaries)
  exit 1 if summaries.any? { |summary| summary["status"] == "failed" }
end
