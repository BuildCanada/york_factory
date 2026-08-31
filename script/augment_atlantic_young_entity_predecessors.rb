#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "date"
require "fileutils"
require "json"
require "optparse"

class AugmentAtlanticYoungEntityPredecessors
  PROFILES = {
    "pe" => {
      scope_id: "ca/pe",
      languages: %w[en],
      source_url: "https://peimunicipalities.princeedwardisland.ca/Municipal-Restructurings",
      source_title: "Municipal Restructuring",
      transitions: [
        [ "ca/pe/brackley", "2017-12-15", [ "Winsloe South", "Brackley" ] ],
        [ "ca/pe/central-prince", "2018-09-28", [ "Ellerslie-Bideford", "Lady Slipper" ] ],
        [ "ca/pe/north-shore", "2018-09-28", [ "North Shore", "Grand Tracadie", "Pleasant Grove" ] ],
        [ "ca/pe/three-rivers", "2018-09-28", [ "Brudenell", "Cardigan", "Georgetown", "Lorne Valley", "Lower Montague", "Montague", "Valleyfield" ] ],
        [ "ca/pe/west-river", "2020-09-01", [ "Afton", "Bonshaw", "Meadow Bank", "New Haven-Riverdale", "West River" ] ]
      ]
    },
    "ns" => {
      scope_id: "ca/ns",
      languages: %w[en],
      source_url: "https://www.novascotia.ca/sites/default/files/documents/1-3251/west-hants-regional-municipality-municipal-profile-and-financial-condition-indicators-results-2021-en.pdf",
      source_title: "West Hants Regional Municipality Municipal Profile and Financial Condition Indicator Results 2021",
      transitions: [
        [ "ca/ns/west-hants", "2020-04-01", [ "Windsor", "West Hants" ] ]
      ]
    }
  }.freeze

  def initialize(manifest:, province:, source_files:)
    @manifest = JSON.parse(File.read(manifest))
    @province = province
    @profile = PROFILES.fetch(province)
    @source_files = source_files
  end

  def call
    assert_inputs!
    rows = @manifest.fetch("municipalities")
    existing_ids = rows.map { _1.fetch("canonical_id") }.to_h { [ _1, true ] }
    additions = []

    @profile.fetch(:transitions).each do |successor_id, effective_on, names|
      names.each do |name|
        id = predecessor_id(name, existing_ids)
        rows << predecessor_row(id, name, effective_on)
        (@manifest["relationships"] ||= []) << relationship_row(successor_id, id, effective_on)
        existing_ids[id] = true
        additions << id
      end
    end

    assert_output!(additions)
    update_metadata!(additions)
    @manifest
  end

  private

  def assert_inputs!
    raise "source files are required" if @source_files.empty?
    missing_files = @source_files.reject { File.file?(_1) }
    raise "source files missing: #{missing_files.join(', ')}" unless missing_files.empty?

    ids = @manifest.fetch("municipalities").map { _1.fetch("canonical_id") }
    missing_ids = @profile.fetch(:transitions).map(&:first) - ids
    raise "successors missing: #{missing_ids.join(', ')}" unless missing_ids.empty?
  end

  def predecessor_id(name, existing_ids)
    slug = name.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\-\z/, "")
    ordinary = "#{@profile.fetch(:scope_id)}/#{slug}"
    return ordinary unless existing_ids.key?(ordinary)

    year = @profile.fetch(:transitions).find { |_id, _date, names| names.include?(name) }[1][0, 4]
    historical = "#{@profile.fetch(:scope_id)}/historical/#{slug}-pre-#{year}"
    raise "historical ID collision: #{historical}" if existing_ids.key?(historical)

    historical
  end

  def predecessor_row(id, name, effective_on)
    active_to = (Date.iso8601(effective_on) - 1).iso8601
    row = {
      "canonical_id" => id,
      "municipality_type" => "former_local_government",
      "tier" => "local",
      "institution_type" => "government",
      "government_level" => "municipal",
      "status" => "dissolved",
      "active_to" => active_to,
      "website_url" => nil,
      "website_source_url" => @profile.fetch(:source_url),
      "website_status" => "historical_not_searched",
      "scrape_gaps" => [ "Historical official website was not searched." ],
      "source_languages" => @profile.fetch(:languages),
      "identifiers" => [],
      "statcan_geographies" => [],
      "documents" => [],
      "sources" => [ source_row ],
      "notes" => "Former incorporated municipality explicitly named by the provincial source as a component of the new successor municipality."
    }
    if @profile.fetch(:languages).include?("fr")
      row["official_name_en"] = name
      row["official_name_fr"] = name
    else
      row["official_name"] = name
    end
    row
  end

  def source_row
    {
      "url" => @profile.fetch(:source_url),
      "source_url" => @profile.fetch(:source_url),
      "publisher_name" => "Government of #{@province == 'pe' ? 'Prince Edward Island' : 'Nova Scotia'}",
      "source_publisher" => "Government of #{@province == 'pe' ? 'Prince Edward Island' : 'Nova Scotia'}",
      "title" => @profile.fetch(:source_title),
      "source_title" => @profile.fetch(:source_title),
      "retrieved_at" => "2026-08-25",
      "source_languages" => @profile.fetch(:languages),
      "languages" => @profile.fetch(:languages)
    }
  end

  def relationship_row(successor_id, predecessor_id, effective_on)
    {
      "source_id" => successor_id,
      "target_id" => predecessor_id,
      "relationship_type" => "succeeds",
      "valid_from" => effective_on,
      "source_url" => @profile.fetch(:source_url),
      "source_title" => @profile.fetch(:source_title),
      "source_languages" => @profile.fetch(:languages)
    }
  end

  def assert_output!(additions)
    expected = @profile.fetch(:transitions).sum { _1[2].length }
    raise "expected #{expected} predecessor rows, got #{additions.length}" unless additions.length == expected
    ids = @manifest.fetch("municipalities").map { _1.fetch("canonical_id") }
    raise "duplicate canonical IDs" unless ids.uniq.length == ids.length
  end

  def update_metadata!(additions)
    @manifest["young_entity_predecessor_augmentation"] = {
      "version" => 1,
      "province" => @province,
      "predecessor_institutions_added" => additions.length,
      "succeeds_edges_added" => additions.length,
      "source_files" => @source_files.map { { "path" => _1, "sha256" => Digest::SHA256.file(_1).hexdigest } },
      "invariant" => "Documents remain attached to the legal institution that issued them; predecessor years are inherited only by traversing a sourced succeeds edge."
    }

    coverage = @manifest.fetch("coverage")
    row = coverage.find { _1["subject"] == "relationships" }
    replacement = {
      "scope_id" => @profile.fetch(:scope_id),
      "subject" => "relationships",
      "status" => "partial",
      "notes" => "Added #{additions.length} authoritative predecessor-to-young-entity transition links. This augmentation covers the cited recent restructurings, not a complete historical municipal genealogy.",
      "source_url" => @profile.fetch(:source_url)
    }
    row ? row.replace(replacement) : coverage << replacement
  end
end

if $PROGRAM_NAME == __FILE__
  options = { source_files: [] }
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby script/augment_atlantic_young_entity_predecessors.rb --province pe|ns --manifest PATH --source-file PATH [--source-file PATH] --output PATH"
    parser.on("--province CODE") { options[:province] = _1 }
    parser.on("--manifest PATH") { options[:manifest] = _1 }
    parser.on("--source-file PATH") { options[:source_files] << _1 }
    parser.on("--output PATH") { options[:output] = _1 }
  end.parse!

  missing = %i[province manifest output].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" unless missing.empty?
  abort "unsupported province" unless AugmentAtlanticYoungEntityPredecessors::PROFILES.key?(options[:province])
  abort "refusing to overwrite #{options[:output]}" if File.exist?(options[:output])

  result = AugmentAtlanticYoungEntityPredecessors.new(
    manifest: options.fetch(:manifest), province: options.fetch(:province), source_files: options.fetch(:source_files)
  ).call
  FileUtils.mkdir_p(File.dirname(options.fetch(:output)))
  File.write(options.fetch(:output), JSON.pretty_generate(result) + "\n")
  puts JSON.pretty_generate(result.fetch("young_entity_predecessor_augmentation"))
end
