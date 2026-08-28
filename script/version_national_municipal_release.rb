#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

class VersionNationalMunicipalRelease
  STALE_UNFETCHED_GAP = /audited municipal PDFs .*not fetched/i

  def initialize(config_path:, output_dir:, output_config:, version:, published_at:)
    @config_path = Pathname(config_path).expand_path
    @output_dir = Pathname(output_dir).expand_path
    @output_config = Pathname(output_config).expand_path
    @version = Date.iso8601(version).iso8601
    @published_at = Time.iso8601(published_at).utc.iso8601
  end

  def run
    raise "missing config #{@config_path}" unless @config_path.file?
    raise "refusing to overwrite #{@output_config}" if @output_config.exist?

    config = JSON.parse(@config_path.read)
    outputs = config.fetch("provinces").to_h do |province|
      code = province.fetch("province")
      [ code, @output_dir.join("#{code}-municipal-institutions-#{@version}.json") ]
    end
    existing = outputs.values.select(&:exist?)
    raise "refusing to overwrite #{existing.join(', ')}" if existing.any?

    FileUtils.mkdir_p(@output_dir)
    config.fetch("provinces").each do |province|
      code = province.fetch("province")
      input = Pathname(province.fetch("manifest_path")).expand_path
      payload = JSON.parse(input.read)
      payload["release_provenance"] = Hash(payload["release_provenance"]).merge(
        "assembled_at" => @published_at,
        "derived_from_manifest_path" => input.to_s,
        "derived_from_manifest_sha256" => Digest::SHA256.file(input).hexdigest,
        "prior_release_version" => payload["release_version"],
        "prior_effective_on" => payload["effective_on"],
        "prior_published_at" => payload["published_at"]
      )
      payload["release_version"] = @version
      payload["effective_on"] = @version
      payload["published_at"] = @published_at
      replace_stale_scrape_gap!(payload)
      write_json(outputs.fetch(code), payload)
      province["manifest_path"] = outputs.fetch(code).to_s
      province["manifest_sha256"] = Digest::SHA256.file(outputs.fetch(code)).hexdigest
      province["scope_note"] = normalize_scope_note(province["scope_note"])
    end

    config["release_version"] = @version
    config["generated_at"] = @published_at
    config["template_status"] = "final_versioned"
    config["derived_from_config_path"] = @config_path.to_s
    config["derived_from_config_sha256"] = Digest::SHA256.file(@config_path).hexdigest
    write_json(@output_config, config)

    puts JSON.pretty_generate(
      "release_version" => @version,
      "published_at" => @published_at,
      "manifest_count" => outputs.length,
      "output_config" => @output_config.to_s,
      "output_config_sha256" => Digest::SHA256.file(@output_config).hexdigest
    )
  end

  private

  def replace_stale_scrape_gap!(payload)
    gaps = Array(payload["scrape_gaps"])
    removed = gaps.reject! { |gap| gap.to_s.match?(STALE_UNFETCHED_GAP) }
    return unless removed

    gaps << "Ten-year financial-statement coverage remains partial; see the versioned national coverage audit " \
      "for exact missing-year and zero-statement gaps."
    payload["scrape_gaps"] = gaps.uniq
  end

  def normalize_scope_note(note)
    note.to_s.sub(/ with at least one validated downloaded financial statement(?=\.)/i, "")
  end

  def write_json(path, payload)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(payload) << "\n")
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: version_national_municipal_release.rb --config PATH --output-dir DIR " \
      "--output-config PATH --version YYYY-MM-DD --published-at ISO8601"
    parser.on("--config PATH") { |value| options[:config_path] = value }
    parser.on("--output-dir DIR") { |value| options[:output_dir] = value }
    parser.on("--output-config PATH") { |value| options[:output_config] = value }
    parser.on("--version DATE") { |value| options[:version] = value }
    parser.on("--published-at TIME") { |value| options[:published_at] = value }
  end.parse!

  missing = %i[config_path output_dir output_config version published_at].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  VersionNationalMunicipalRelease.new(**options).run
end
