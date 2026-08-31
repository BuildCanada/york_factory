#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "pathname"
require "time"
require "uri"

class ApplyMunicipalWebsiteOverrides
  def initialize(manifest_path:, overrides_path:, output_path:, transformed_at:)
    @manifest_path = Pathname(manifest_path).expand_path
    @overrides_path = Pathname(overrides_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @transformed_at = Time.iso8601(transformed_at).utc
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    rows = manifest.fetch("municipalities").to_h { |row| [ row.fetch("canonical_id"), row ] }
    overrides = JSON.parse(@overrides_path.read).fetch("overrides")
    raise "duplicate override canonical IDs" unless overrides.map { _1.fetch("canonical_id") }.uniq.length == overrides.length

    changes = overrides.map do |override|
      apply_override(rows.fetch(override.fetch("canonical_id")), override)
    end
    manifest["municipal_website_overrides"] = {
      "transformed_at" => @transformed_at.iso8601,
      "source_manifest_path" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "overrides_path" => @overrides_path.to_s,
      "overrides_sha256" => Digest::SHA256.file(@overrides_path).hexdigest,
      "change_count" => changes.length,
      "changes" => changes
    }
    @output_path.dirname.mkpath
    @output_path.write(JSON.pretty_generate(manifest) << "\n")
    puts JSON.pretty_generate(
      "output" => @output_path.to_s,
      "output_sha256" => Digest::SHA256.file(@output_path).hexdigest,
      "change_count" => changes.length,
      "changes" => changes
    )
  end

  private

  def apply_override(row, override)
    website_url = valid_http_url!(override.fetch("website_url"), "website_url")
    source_url = valid_http_url!(override.fetch("source_url"), "source_url")
    previous_url = row["website_url"]
    if previous_url && URI(previous_url).host.to_s.downcase.sub(/\Awww\./, "") == "municipalnl.ca"
      row["website_directory_profile_url"] ||= previous_url
    end
    row["website_url"] = website_url
    row["website_source_url"] = source_url
    row["website_status"] = "verified_official_site"
    row.delete("website_gap")
    {
      "canonical_id" => row.fetch("canonical_id"),
      "previous_website_url" => previous_url,
      "website_url" => website_url,
      "source_url" => source_url,
      "evidence" => override["evidence"]
    }.compact
  end

  def valid_http_url!(value, field)
    uri = URI(value)
    raise "#{field} must be an absolute HTTP(S) URL" unless %w[http https].include?(uri.scheme) && uri.host

    uri.to_s
  rescue URI::InvalidURIError
    raise "#{field} must be an absolute HTTP(S) URL"
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: apply_municipal_website_overrides.rb --manifest PATH --overrides PATH --output PATH --transformed-at ISO8601"
    parser.on("--manifest PATH") { options[:manifest_path] = _1 }
    parser.on("--overrides PATH") { options[:overrides_path] = _1 }
    parser.on("--output PATH") { options[:output_path] = _1 }
    parser.on("--transformed-at ISO8601") { options[:transformed_at] = _1 }
  end.parse!

  missing = %i[manifest_path overrides_path output_path transformed_at].reject { options[_1] }
  abort "missing options: #{missing.join(', ')}" if missing.any?

  ApplyMunicipalWebsiteOverrides.new(**options).run
end
