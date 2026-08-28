#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

class CorrectDuplicateAnnualReportAssets
  BC_PAAC = "405ec8553ea2d37763b1b279177523fbfd61a5ce88423be3541afe9293d682f1"
  NB_NONMUNICIPAL = %w[
    8f787dfd9225a6e1990fdeff0fb16f193307d1596c9e670f4d364e1283553f45
    a7c0bd6ead0ee07c8a38525b7e19f2270d67cc7355b34824cba3d78583ea6d2f
    1723429212eb5fd39292a2500fa1d0289525a43abe987229aae6be1bc56c090d
  ].freeze
  LE_GOULET_REPORT = "c9b035b0cf70d3ba49660cd09750d0f087ecec111ed341692caabb9abea254bd"
  LE_GOULET = "ca/nb/le-goulet"

  def initialize(config_path:, output_dir:, output_config:, published_at:)
    @config_path = Pathname(config_path).expand_path
    @output_dir = Pathname(output_dir).expand_path
    @output_config = Pathname(output_config).expand_path
    @published_at = Time.iso8601(published_at).utc.iso8601
    @decisions = []
  end

  def run
    raise "missing config #{@config_path}" unless @config_path.file?
    raise "refusing to overwrite #{@output_config}" if @output_config.exist?

    config = JSON.parse(@config_path.read)
    FileUtils.mkdir_p(@output_dir)
    config.fetch("provinces").each do |province|
      input = Pathname(province.fetch("manifest_path")).expand_path
      output = @output_dir.join(input.basename)
      raise "refusing to overwrite #{output}" if output.exist?

      manifest = JSON.parse(input.read)
      correct_manifest!(province.fetch("province"), manifest)
      manifest["published_at"] = @published_at
      manifest["release_provenance"] = Hash(manifest["release_provenance"]).merge(
        "annual_report_correction_at" => @published_at,
        "annual_report_correction_from_path" => input.to_s,
        "annual_report_correction_from_sha256" => Digest::SHA256.file(input).hexdigest
      )
      write_json(output, manifest)
      province["manifest_path"] = output.to_s
      province["manifest_sha256"] = Digest::SHA256.file(output).hexdigest
    end

    config["generated_at"] = @published_at
    config["template_status"] = "final_versioned_corrected"
    config["derived_from_config_path"] = @config_path.to_s
    config["derived_from_config_sha256"] = Digest::SHA256.file(@config_path).hexdigest
    config["annual_report_asset_corrections"] = @decisions
    write_json(@output_config, config)
    puts JSON.pretty_generate(
      "output_config" => @output_config.to_s,
      "output_config_sha256" => Digest::SHA256.file(@output_config).hexdigest,
      "removed_asset_link_count" => @decisions.length
    )
  end

  private

  def correct_manifest!(province, manifest)
    manifest.fetch("municipalities").each do |institution|
      documents = Array(institution["documents"])
      documents.each do |document|
        next unless document["document_type"] == "annual-report"

        original_assets = Array(document["assets"])
        document["assets"] = original_assets.reject do |asset|
          reason = removal_reason(province, institution.fetch("canonical_id"), asset["content_sha256"])
          next false unless reason

          @decisions << {
            "province" => province,
            "institution_id" => institution.fetch("canonical_id"),
            "document_id" => document.fetch("canonical_id"),
            "content_sha256" => asset.fetch("content_sha256"),
            "reason" => reason
          }
          true
        end
        normalize_assets!(document["assets"])
        le_goulet_report = province == "nb" && institution.fetch("canonical_id") == LE_GOULET &&
          document["assets"].any? { _1["content_sha256"] == LE_GOULET_REPORT }
        if document["assets"].any? && (document["assets"].length != original_assets.length || le_goulet_report)
          document["download_url"] = document["assets"].first["download_url"]
        end
      end
      documents.reject! { |document| document["document_type"] == "annual-report" && Array(document["assets"]).empty? }
    end
  end

  def removal_reason(province, institution_id, digest)
    return "Peninsula Agricultural Advisory Commission report is not a municipal annual report." if province == "bc" && digest == BC_PAAC
    return "Patrimoine Shippagan Inc. report is nonmunicipal." if province == "nb" && NB_NONMUNICIPAL.include?(digest)
    return unless province == "nb" && digest == LE_GOULET_REPORT && institution_id != LE_GOULET

    "PDF identifies the former Village de Le Goulet; retain only on that issuer."
  end

  def normalize_assets!(assets)
    assets.each_with_index do |asset, index|
      asset["preferred"] = index.zero?
      asset["part_index"] = assets.length > 1 ? index + 1 : nil
      asset["part_count"] = assets.length > 1 ? assets.length : nil
    end
  end

  def write_json(path, payload)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(payload) << "\n")
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.on("--config PATH") { |value| options[:config_path] = value }
    parser.on("--output-dir DIR") { |value| options[:output_dir] = value }
    parser.on("--output-config PATH") { |value| options[:output_config] = value }
    parser.on("--published-at TIME") { |value| options[:published_at] = value }
  end.parse!
  missing = %i[config_path output_dir output_config published_at].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  CorrectDuplicateAnnualReportAssets.new(**options).run
end
