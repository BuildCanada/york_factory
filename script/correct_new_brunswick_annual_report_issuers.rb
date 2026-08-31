#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"

class CorrectNewBrunswickAnnualReportIssuers
  OLD_EDMUNDSTON = "ca/nb/historical/edmundston-pre-2023"
  OLD_SHIPPAGAN = "ca/nb/historical/shippagan-pre-2023"
  LE_GOULET = "ca/nb/le-goulet"

  DECISIONS = {
    "d97d28274fe7587b2822fa6502066165ae70dec38418008eb65795c421be70bd" => [ OLD_EDMUNDSTON, /city of edmundston/i, "The cover identifies City of Edmundston." ],
    "0f735182703b051c8020dfb996260266875ff2c97744535974fdd6cb5eef5ff1" => [ OLD_EDMUNDSTON, /city of edmundston/i, "The cover identifies City of Edmundston." ],
    "d3d007e290d995bbc4dd55d82f08ef3c69d193dac6b552eaeffd10d77d8a0b74" => [ OLD_EDMUNDSTON, /city of edmundston/i, "The cover identifies City of Edmundston." ],
    "7c72ca254179c0795530d1ec7289c6ba3cdf5754b18bbf3840c3fb054781064c" => [ OLD_EDMUNDSTON, /before the amalgamation with rivière-verte/i, "The report says it covers Edmundston before amalgamation with Rivière-Verte." ],
    "d1fbec351aac5861320b2eeddfe52fa1415a872fc361869984aae0a8ab9d52f1" => [ OLD_EDMUNDSTON, /avant le regroupement avec rivière-verte/i, "The French report says it covers Edmundston before amalgamation with Rivière-Verte." ],
    "8f787dfd9225a6e1990fdeff0fb16f193307d1596c9e670f4d364e1283553f45" => [ nil, /patrimoine shippagan inc/i, "The report identifies Patrimoine Shippagan Inc., not a municipality." ],
    "c9b035b0cf70d3ba49660cd09750d0f087ecec111ed341692caabb9abea254bd" => [ LE_GOULET, /village de le goulet/i, "The cover identifies Village de Le Goulet." ],
    "a7c0bd6ead0ee07c8a38525b7e19f2270d67cc7355b34824cba3d78583ea6d2f" => [ nil, /patrimoine shippagan inc/i, "The report identifies Patrimoine Shippagan Inc., not a municipality." ],
    "1723429212eb5fd39292a2500fa1d0289525a43abe987229aae6be1bc56c090d" => [ nil, /patrimoine shippagan inc/i, "The report identifies Patrimoine Shippagan Inc., not a municipality." ],
    "23d4035a2ef289cd5c75f3e290a405c1e087e6d7e0a2bde81dfdfa8b12f5588b" => [ OLD_SHIPPAGAN, /rapport annuel de la ville de\s+shippagan/i, "The mayor's message identifies the annual report of Ville de Shippagan." ],
    "27a47f8e33f1737385a809aa07fd2ab47b5fddfe5c54be9c17a6af56d945945b" => [ OLD_SHIPPAGAN, /ville de shippagan/i, "The mayor's message identifies Ville de Shippagan." ]
  }.freeze

  SOURCE_IDS = %w[ca/nb/edmundston ca/nb/shippagan].freeze

  def initialize(manifest:, asset_root:)
    @manifest = JSON.parse(File.read(manifest))
    @asset_root = asset_root
    @audit_rows = []
  end

  def call
    rows = @manifest.fetch("municipalities")
    by_id = rows.to_h { [ _1.fetch("canonical_id"), _1 ] }
    [ OLD_EDMUNDSTON, OLD_SHIPPAGAN, LE_GOULET ].each { by_id.fetch(_1) }

    candidates = SOURCE_IDS.flat_map do |source_id|
      source = by_id.fetch(source_id)
      source.fetch("documents", []).select do |document|
        document["document_type"] == "annual-report" && year(document) < 2023
      end.map { |document| [ source, document ] }
    end
    raise "expected eight pre-reform annual-report works, found #{candidates.length}" unless candidates.length == 8

    candidates.each { |source, document| correct_document!(source, document, by_id) }
    assert_output!
    update_metadata!
    [ @manifest, audit_payload ]
  end

  private

  def correct_document!(source, document, by_id)
    grouped = Hash.new { |hash, key| hash[key] = [] }
    document.fetch("assets").each do |asset|
      digest = asset.fetch("content_sha256")
      target_id, proof_pattern, evidence = DECISIONS.fetch(digest)
      text = extract_text(asset)
      raise "issuer proof absent from #{digest}" unless text.match?(proof_pattern)

      grouped[target_id] << asset
      @audit_rows << {
        "source_institution_id" => source.fetch("canonical_id"),
        "source_document_id" => document.fetch("canonical_id"),
        "content_sha256" => digest,
        "archive_path" => asset.fetch("archive_path"),
        "decision" => target_id ? "move_to_issuer" : "exclude_nonmunicipal_from_municipal_ontology",
        "target_institution_id" => target_id,
        "pdf_content_evidence" => evidence
      }
    end

    source.fetch("documents").delete(document)
    grouped.each do |target_id, assets|
      next unless target_id

      target = by_id.fetch(target_id)
      corrected = deep_copy_json(document)
      corrected["assets"] = normalize_assets(assets)
      corrected["canonical_id"] = "#{target_id}/documents/annual-report/#{year(document)}/general"
      set_titles!(corrected, target, year(document))
      corrected["notes"] = [ corrected["notes"], "Issuer identity corrected using text extracted from each retained PDF asset." ].compact.join(" ")
      target.fetch("documents") << corrected
    end
  end

  def extract_text(asset)
    path = File.join(@asset_root, asset.fetch("archive_path"))
    raise "asset missing: #{path}" unless File.file?(path)
    raise "asset hash mismatch: #{path}" unless Digest::SHA256.file(path).hexdigest == asset.fetch("content_sha256")

    stdout, stderr, status = Open3.capture3("pdftotext", "-f", "1", "-l", "8", "-layout", path, "-")
    raise "pdftotext failed for #{path}: #{stderr}" unless status.success?

    stdout.unicode_normalize(:nfc)
  end

  def normalize_assets(assets)
    assets.each_with_index.map do |asset, index|
      copy = deep_copy_json(asset)
      copy["preferred"] = index.zero?
      copy["part_index"] = nil
      copy["part_count"] = nil
      copy
    end
  end

  def set_titles!(document, target, fiscal_year)
    name = target["official_name_en"] || target["official_name"] || target["official_name_fr"]
    languages = document.fetch("assets").flat_map { _1.fetch("languages", []) }.uniq
    document["title"] = languages.include?("en") ? "#{name} Annual Report — #{fiscal_year}" : nil
    document["title_fr"] = languages.include?("fr") ? "#{name} Rapport annuel — #{fiscal_year}" : nil
    document["source_languages"] = languages unless languages.empty?
  end

  def deep_copy_json(value)
    JSON.parse(JSON.generate(value))
  end

  def year(document)
    document.fetch("canonical_id")[%r{/([12]\d{3})/}, 1].to_i
  end

  def assert_output!
    raise "expected eleven asset decisions" unless @audit_rows.length == 11
    raise "expected eight moved municipal asset links" unless @audit_rows.count { _1["decision"] == "move_to_issuer" } == 8
    raise "expected three excluded nonprofit asset links" unless @audit_rows.count { _1["decision"].start_with?("exclude_") } == 3

    ids = @manifest.fetch("municipalities").flat_map { _1.fetch("documents", []).map { |document| document.fetch("canonical_id") } }
    raise "duplicate document canonical IDs" unless ids.uniq.length == ids.length

    leftovers = @manifest.fetch("municipalities").select { SOURCE_IDS.include?(_1.fetch("canonical_id")) }.flat_map do |row|
      row.fetch("documents", []).select { _1["document_type"] == "annual-report" && year(_1) < 2023 }
    end
    raise "pre-reform annual reports remain on successor IDs" unless leftovers.empty?
  end

  def update_metadata!
    @manifest["annual_report_issuer_correction"] = audit_payload
    institutions = @manifest.fetch("municipalities")
    annual_assets = institutions.sum do |row|
      row.fetch("documents", []).select { _1["document_type"] == "annual-report" }.sum { _1.fetch("assets", []).length }
    end
    all_assets = institutions.sum { |row| row.fetch("documents", []).sum { _1.fetch("assets", []).length } }
    current_with_annuals = institutions.reject { _1["status"] == "dissolved" }.count do |row|
      row.fetch("documents", []).any? { _1["document_type"] == "annual-report" && _1.fetch("assets", []).any? }
    end
    replace_coverage!("annual-reports", "partial", "#{current_with_annuals} current institutions have archived annual-report assets. Eight pre-reform municipal asset links were moved to their PDF-identified predecessor issuers; three Patrimoine Shippagan Inc. links were excluded as nonmunicipal. #{annual_assets} annual-report asset links remain across current and historical institutions.")
    replace_coverage!("document-assets", "partial", "#{all_assets} SHA-256-addressed document-asset links remain after issuer correction. No archived bytes were deleted; three nonmunicipal links were removed from this municipal manifest.")
  end

  def replace_coverage!(subject, status, notes)
    row = @manifest.fetch("coverage").find { _1["subject"] == subject }
    value = { "scope_id" => "ca/nb", "subject" => subject, "status" => status, "notes" => notes, "source_url" => nil }
    row ? row.replace(value) : @manifest.fetch("coverage") << value
  end

  def audit_payload
    {
      "artifact" => "new_brunswick_pre_reform_annual_report_issuer_audit",
      "version" => 1,
      "status" => "complete",
      "method" => "PDF text from pages 1–8; no issuer decision was made from a URL or title alone.",
      "asset_decision_count" => @audit_rows.length,
      "moved_municipal_asset_link_count" => @audit_rows.count { _1["decision"] == "move_to_issuer" },
      "excluded_nonmunicipal_asset_link_count" => @audit_rows.count { _1["decision"].start_with?("exclude_") },
      "archived_byte_deletion_count" => 0,
      "decisions" => @audit_rows
    }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby script/correct_new_brunswick_annual_report_issuers.rb --manifest PATH --asset-root PATH --output PATH --audit-output PATH"
    parser.on("--manifest PATH") { options[:manifest] = _1 }
    parser.on("--asset-root PATH") { options[:asset_root] = _1 }
    parser.on("--output PATH") { options[:output] = _1 }
    parser.on("--audit-output PATH") { options[:audit_output] = _1 }
  end.parse!
  missing = %i[manifest asset_root output audit_output].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" unless missing.empty?
  abort "refusing to overwrite output" if File.exist?(options[:output]) || File.exist?(options[:audit_output])

  manifest, audit = CorrectNewBrunswickAnnualReportIssuers.new(
    manifest: options.fetch(:manifest), asset_root: options.fetch(:asset_root)
  ).call
  FileUtils.mkdir_p(File.dirname(options.fetch(:output)))
  File.write(options.fetch(:output), JSON.pretty_generate(manifest) + "\n")
  File.write(options.fetch(:audit_output), JSON.pretty_generate(audit) + "\n")
  puts JSON.pretty_generate(audit.reject { _1 == "decisions" })
end
