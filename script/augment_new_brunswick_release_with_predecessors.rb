#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"

class AugmentNewBrunswickReleaseWithPredecessors
  REGULATION_URL = "https://laws.gnb.ca/en/document/cr/2022-50"
  EFFECTIVE_ON = "2023-01-01"
  PREDECESSOR_ACTIVE_TO = "2022-12-31"

  # Section => [current successor ID, predecessor corporate names]. A section
  # saying that a body is "continued" is intentionally absent: that is the
  # same legal institution, not a predecessor/successor transition.
  TRANSITIONS = {
    4 => [ "ca/nb/campbellton", [ "Campbellton", "Atholville", "Tide Head" ] ],
    6 => [ "ca/nb/edmundston", [ "Edmundston", "Rivière-Verte" ] ],
    11 => [ "ca/nb/heron-bay", [ "Dalhousie", "Charlo" ] ],
    12 => [ "ca/nb/beaurivage", [ "Richibucto", "Saint-Louis de Kent" ] ],
    13 => [ "ca/nb/belle-baie", [ "Beresford", "Nigadoo", "Petit-Rocher", "Pointe-Verte" ] ],
    14 => [ "ca/nb/cap-acadie", [ "Beaubassin East", "Cap-Pélé" ] ],
    15 => [ "ca/nb/caraquet", [ "Caraquet", "Bas-Caraquet" ] ],
    16 => [ "ca/nb/carleton-north", [ "Florenceville-Bristol", "Bath", "Centreville" ] ],
    17 => [ "ca/nb/champdore", [ "Saint-Antoine" ] ],
    20 => [ "ca/nb/grand-sault", [ "Grand Falls", "Drummond", "Saint-André" ] ],
    23 => [ "ca/nb/hautes-terres", [ "Saint-Isidore", "Paquetville" ] ],
    24 => [ "ca/nb/haut-madawaska", [ "Haut-Madawaska", "Lac Baker" ] ],
    25 => [ "ca/nb/ile-de-lameque", [ "Lamèque", "Sainte-Marie-Saint-Raphaël" ] ],
    29 => [ "ca/nb/riviere-du-nord", [ "Bertrand", "Maisonnette", "Grande-Anse", "Saint-Léolin" ] ],
    33 => [ "ca/nb/salisbury", [ "Salisbury" ] ],
    35 => [ "ca/nb/shippagan", [ "Shippagan", "Le Goulet" ] ],
    37 => [ "ca/nb/sussex", [ "Sussex", "Sussex Corner" ] ],
    38 => [ "ca/nb/tantramar", [ "Sackville", "Dorchester" ] ],
    39 => [ "ca/nb/vallee-des-rivieres", [ "Saint-Léonard", "Sainte-Anne-de-Madawaska" ] ],
    41 => [ "ca/nb/arcadia", [ "Cambridge-Narrows", "Gagetown" ] ],
    43 => [ "ca/nb/bois-joli", [ "Balmoral", "Eel River Crossing" ] ],
    47 => [ "ca/nb/fundy-albert", [ "Alma", "Riverside-Albert", "Hillsborough" ] ],
    49 => [ "ca/nb/grand-lake", [ "Minto", "Chipman" ] ],
    51 => [ "ca/nb/lakeland-ridges", [ "Canterbury", "Meductic" ] ],
    57 => [ "ca/nb/southern-victoria", [ "Aroostook", "Perth-Andover" ] ],
    67 => [ "ca/nb/eastern-charlotte", [ "St. George", "Blacks Harbour" ] ],
    70 => [ "ca/nb/harvey", [ "Harvey" ] ],
    73 => [ "ca/nb/miramichi-river-valley", [ "Blackville" ] ],
    74 => [ "ca/nb/nackawic-millville", [ "Nackawic", "Millville" ] ],
    75 => [ "ca/nb/nashwaak", [ "Stanley" ] ],
    76 => [ "ca/nb/strait-shores", [ "Port Elgin" ] ]
  }.freeze

  # Only documents whose issuer is explicit in the source asset are moved.
  # The key is [current successor, fiscal year].
  FINANCIAL_DOCUMENT_ISSUERS = {
    [ "ca/nb/edmundston", 2019 ] => "Edmundston",
    [ "ca/nb/edmundston", 2022 ] => "Edmundston",
    [ "ca/nb/caraquet", 2021 ] => "Caraquet",
    [ "ca/nb/haut-madawaska", 2020 ] => "Haut-Madawaska",
    [ "ca/nb/haut-madawaska", 2022 ] => "Lac Baker",
    [ "ca/nb/salisbury", 2018 ] => "Salisbury",
    [ "ca/nb/salisbury", 2020 ] => "Salisbury",
    [ "ca/nb/salisbury", 2021 ] => "Salisbury",
    [ "ca/nb/salisbury", 2022 ] => "Salisbury",
    [ "ca/nb/shippagan", 2021 ] => "Shippagan",
    [ "ca/nb/shippagan", 2022 ] => "Shippagan",
    [ "ca/nb/southern-victoria", 2022 ] => "Perth-Andover"
  }.freeze

  attr_reader :moves

  def initialize(manifest:, audit:, source_pdf:)
    @manifest = JSON.parse(File.read(manifest))
    @audit = JSON.parse(File.read(audit))
    @source_pdf = Pathname(source_pdf)
    @moves = []
  end

  def call
    assert_inputs!
    existing_ids = @manifest.fetch("municipalities").map { _1.fetch("canonical_id") }.to_h { [ _1, true ] }
    predecessor_by_key = {}

    TRANSITIONS.each do |section, (successor_id, predecessor_names)|
      clause = audit_section(section).fetch("english_subsection_1")
      predecessor_names.each do |name|
        id = predecessor_id(name, existing_ids)
        predecessor_by_key[[ successor_id, name ]] = id
        @manifest.fetch("municipalities") << predecessor_row(id, name, section, clause)
        @manifest["relationships"] ||= []
        @manifest["relationships"] << relationship_row(successor_id, id, section, clause)
        existing_ids[id] = true
      end
    end

    move_financial_documents!(predecessor_by_key)
    assert_output!
    update_metadata!
    @manifest
  end

  def predecessor_id(name, existing_ids)
    slug = name.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\-\z/, "")
    ordinary = "ca/nb/#{slug}"
    return ordinary unless existing_ids.key?(ordinary)

    historical = "ca/nb/historical/#{slug}-pre-2023"
    raise "historical canonical-ID collision: #{historical}" if existing_ids.key?(historical)

    historical
  end

  private

  def assert_inputs!
    raise "expected 64 predecessor institutions" unless TRANSITIONS.sum { |_section, (_id, names)| names.length } == 64
    raise "regulation PDF is missing: #{@source_pdf}" unless @source_pdf.file?

    ids = @manifest.fetch("municipalities").map { _1.fetch("canonical_id") }
    missing = TRANSITIONS.values.map(&:first).uniq - ids
    raise "successor IDs missing from manifest: #{missing.join(', ')}" unless missing.empty?

    classifications = @audit.fetch("sections").to_h { [ _1.fetch("section"), _1.fetch("classification") ] }
    bad = TRANSITIONS.keys.reject { %w[amalgamation_new_body resident_incorporation_new_body].include?(classifications[_1]) }
    raise "transition sections not classified as new bodies: #{bad.join(', ')}" unless bad.empty?
  end

  def audit_section(number)
    @audit.fetch("sections").find { _1.fetch("section") == number } || raise("audit section #{number} missing")
  end

  def predecessor_row(id, name, section, clause)
    {
      "canonical_id" => id,
      "official_name_en" => name,
      "official_name_fr" => name,
      "municipality_type" => "former_local_government",
      "tier" => "local",
      "institution_type" => "government",
      "government_level" => "municipal",
      "status" => "dissolved",
      "active_to" => PREDECESSOR_ACTIVE_TO,
      "website_url" => nil,
      "website_source_url" => "#{REGULATION_URL}##{section}",
      "website_status" => "historical_not_searched",
      "scrape_gaps" => [ "Historical official website was not searched." ],
      "source_languages" => [ "en", "fr" ],
      "identifiers" => [],
      "statcan_geographies" => [],
      "documents" => [],
      "sources" => [
        {
          "source_url" => "#{REGULATION_URL}##{section}",
          "source_title" => "New Brunswick Regulation 2022-50, section #{section}",
          "source_publisher" => "Government of New Brunswick",
          "source_languages" => [ "en", "fr" ],
          "retrieved_on" => "2026-08-25",
          "evidence" => clause
        }
      ],
      "notes" => "Former incorporated local government named in section #{section} of New Brunswick Regulation 2022-50; it ceased to be the reporting legal entity at the 2023 local-governance restructuring."
    }
  end

  def relationship_row(successor_id, predecessor_id, section, clause)
    {
      "source_id" => successor_id,
      "target_id" => predecessor_id,
      "relationship_type" => "succeeds",
      "valid_from" => EFFECTIVE_ON,
      "source_url" => "#{REGULATION_URL}##{section}",
      "source_title" => "New Brunswick Regulation 2022-50, section #{section}",
      "source_languages" => [ "en", "fr" ],
      "evidence" => clause
    }
  end

  def move_financial_documents!(predecessor_by_key)
    rows = @manifest.fetch("municipalities").to_h { [ _1.fetch("canonical_id"), _1 ] }
    FINANCIAL_DOCUMENT_ISSUERS.each do |(successor_id, year), predecessor_name|
      successor = rows.fetch(successor_id)
      matches = successor.fetch("documents", []).select do |document|
        document["document_type"] == "financial-statements" && document_year(document) == year
      end
      raise "expected exactly one #{successor_id} financial statement for #{year}, found #{matches.length}" unless matches.one?

      document = matches.first
      successor.fetch("documents").delete(document)
      predecessor_id = predecessor_by_key.fetch([ successor_id, predecessor_name ])
      predecessor = rows.fetch(predecessor_id)
      old_id = document.fetch("canonical_id")
      variant = document["document_variant"] || "general"
      document["canonical_id"] = "#{predecessor_id}/documents/financial-statements/#{year}/#{variant}"
      document["notes"] = [ document["notes"], "Issuer identity corrected to #{predecessor_name}; the post-2023 successor did not issue this pre-reform statement." ].compact.join(" ")
      predecessor.fetch("documents") << document
      @moves << {
        "from_institution_id" => successor_id,
        "to_institution_id" => predecessor_id,
        "fiscal_year" => year,
        "old_document_id" => old_id,
        "new_document_id" => document.fetch("canonical_id"),
        "asset_sha256s" => document.fetch("assets", []).map { _1["content_sha256"] }.compact
      }
    end
  end

  def document_year(document)
    value = document["fiscal_period_end"] || document["published_on"]
    return value.to_s[0, 4].to_i if value.to_s.match?(/\A\d{4}/)

    document.fetch("canonical_id")[%r{/([12]\d{3})/}, 1]&.to_i
  end

  def assert_output!
    raise "expected 12 moved financial-statement works, got #{@moves.length}" unless @moves.length == 12

    institutions = @manifest.fetch("municipalities")
    institution_ids = institutions.map { _1.fetch("canonical_id") }
    raise "duplicate institution canonical IDs" unless institution_ids.uniq.length == institution_ids.length

    document_ids = institutions.flat_map { _1.fetch("documents", []).map { |document| document.fetch("canonical_id") } }
    raise "duplicate document canonical IDs" unless document_ids.uniq.length == document_ids.length

    misplaced = institutions.select { _1.fetch("status", "active") == "active" }.flat_map do |row|
      row.fetch("documents", []).filter_map do |document|
        year = document_year(document)
        [ row.fetch("canonical_id"), year ] if document["document_type"] == "financial-statements" && FINANCIAL_DOCUMENT_ISSUERS.key?([ row.fetch("canonical_id"), year ])
      end
    end
    raise "pre-reform financial statements remain on successors: #{misplaced.inspect}" unless misplaced.empty?
  end

  def update_metadata!
    institutions = @manifest.fetch("municipalities")
    current = institutions.reject { _1["status"] == "dissolved" }
    historical = institutions.select { _1["status"] == "dissolved" }
    current_reporting = current.reject { _1["municipality_type"] == "rural_district" }
    with_financials = current_reporting.count { |row| row.fetch("documents", []).any? { _1["document_type"] == "financial-statements" && _1.fetch("assets", []).any? } }
    assets = institutions.sum { |row| row.fetch("documents", []).sum { _1.fetch("assets", []).length } }

    replace_coverage!("institutions", "complete", "#{current.length} current institutions and #{historical.length} explicitly modelled predecessor institutions are emitted. Predecessors are separate legal identities and are not added to the current-roster denominator.", REGULATION_URL)
    replace_coverage!("relationships", "complete", "#{@manifest.fetch('relationships').count { _1['relationship_type'] == 'succeeds' }} sourced succeeds edges represent every incorporated predecessor explicitly named in the new-body clauses of New Brunswick Regulation 2022-50. Continuations and unincorporated territory are not fabricated as predecessor institutions.", REGULATION_URL)
    replace_coverage!("financial-statements", "partial", "#{with_financials} of #{current_reporting.length} current financial-reporting institutions have a locally archived financial statement issued by that institution. Twelve pre-reform works were moved to their actual predecessor issuers; predecessor years may be counted only through sourced succeeds edges.", nil)
    replace_coverage!("document-assets", "partial", "#{assets} SHA-256-addressed document-asset links are present across current and historical institutions; moving issuer ownership does not duplicate underlying archived bytes.", nil)

    @manifest["predecessor_identity_correction"] = {
      "version" => 1,
      "effective_on" => EFFECTIVE_ON,
      "legal_source_url" => REGULATION_URL,
      "legal_source_pdf" => @source_pdf.to_s,
      "legal_source_pdf_sha256" => Digest::SHA256.file(@source_pdf).hexdigest,
      "predecessor_institutions_added" => historical.length,
      "succeeds_edges_added" => TRANSITIONS.sum { |_section, (_id, names)| names.length },
      "financial_statement_works_moved" => @moves.length,
      "moves" => @moves,
      "counting_rule" => "A document remains on its issuer. A current institution may inherit historical coverage only by traversing a sourced succeeds edge; no predecessor document is relabelled as successor-issued."
    }
  end

  def replace_coverage!(subject, status, notes, source_url)
    coverage = @manifest.fetch("coverage")
    row = coverage.find { _1["subject"] == subject }
    value = { "scope_id" => "ca/nb", "subject" => subject, "status" => status, "notes" => notes, "source_url" => source_url }
    row ? row.replace(value) : coverage << value
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby script/augment_new_brunswick_release_with_predecessors.rb --manifest PATH --audit PATH --source-pdf PATH --output PATH"
    parser.on("--manifest PATH") { options[:manifest] = _1 }
    parser.on("--audit PATH") { options[:audit] = _1 }
    parser.on("--source-pdf PATH") { options[:source_pdf] = _1 }
    parser.on("--output PATH") { options[:output] = _1 }
  end.parse!

  missing = %i[manifest audit source_pdf output].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" unless missing.empty?
  abort "refusing to overwrite #{options[:output]}" if File.exist?(options[:output])

  result = AugmentNewBrunswickReleaseWithPredecessors.new(
    manifest: options.fetch(:manifest), audit: options.fetch(:audit), source_pdf: options.fetch(:source_pdf)
  ).call
  FileUtils.mkdir_p(File.dirname(options.fetch(:output)))
  File.write(options.fetch(:output), JSON.pretty_generate(result) + "\n")
  puts JSON.generate(result.fetch("predecessor_identity_correction"))
end
