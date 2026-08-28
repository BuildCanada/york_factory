#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "optparse"
require "pathname"
require "thread"
require "time"
require "uri"

class BackfillNewfoundlandMunicipalWebsites
  USER_AGENT = "YorkFactory public-government-data crawler; contact data@buildcanada.com"
  DIRECTORY_HOST = "municipalnl.ca"
  SOCIAL_HOSTS = %w[
    facebook.com instagram.com linkedin.com tiktok.com twitter.com x.com youtube.com
  ].freeze

  def initialize(manifest_path:, output_path:, audit_path:, raw_dir:, retrieved_at:, threads: 8)
    @manifest_path = Pathname(manifest_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @audit_path = Pathname(audit_path).expand_path
    @raw_dir = Pathname(raw_dir).expand_path
    @retrieved_at = Time.iso8601(retrieved_at).utc
    @threads = Integer(threads)
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?
    raise "refusing to overwrite #{@audit_path}" if @audit_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    rows = manifest.fetch("municipalities")
    work = rows.select { directory_profile?(_1["website_url"]) }
    FileUtils.mkdir_p(@raw_dir)
    results = parallel_map(work) { extract_profile(_1) }
    by_id = rows.to_h { [ _1.fetch("canonical_id"), _1 ] }
    results.each do |result|
      next unless result["official_website_url"]

      row = by_id.fetch(result.fetch("canonical_id"))
      row["website_directory_profile_url"] = row["website_url"]
      row["website_url"] = result.fetch("official_website_url")
      row["website_source_url"] = result.fetch("profile_url")
      row["website_status"] = "verified_association_directory_external_link"
      row.delete("website_gap")
    end
    update_coverage!(manifest, rows)
    manifest["newfoundland_official_website_backfill"] = {
      "retrieved_at" => @retrieved_at.iso8601,
      "source_directory" => "https://municipalnl.ca/directory/",
      "source_manifest_path" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "audit_path" => @audit_path.to_s,
      "raw_directory" => @raw_dir.to_s
    }
    audit = {
      "retrieved_at" => @retrieved_at.iso8601,
      "source_manifest_path" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "profile_count" => results.length,
      "official_websites_discovered" => results.count { _1["official_website_url"] },
      "profiles_without_official_websites" => results.count { !_1["official_website_url"] },
      "results" => results.sort_by { _1.fetch("canonical_id") }
    }
    write_json(@audit_path, audit)
    write_json(@output_path, manifest)
    puts JSON.pretty_generate(audit.except("results").merge(
      "output" => @output_path.to_s,
      "audit" => @audit_path.to_s,
      "output_sha256" => Digest::SHA256.file(@output_path).hexdigest,
      "audit_sha256" => Digest::SHA256.file(@audit_path).hexdigest
    ))
  end

  private

  def extract_profile(row)
    profile_url = row.fetch("website_url")
    html = fetch(profile_url)
    raw_path = @raw_dir.join("#{row.fetch('canonical_id').tr('/', '_')}.html")
    raw_path.binwrite(html)
    document = Nokogiri::HTML(html)
    section = profile_section(document)
    candidates = external_links(section || document)
    {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => official_name(row),
      "profile_url" => profile_url,
      "official_website_url" => choose_official_url(candidates, row),
      "external_candidates" => candidates,
      "raw_path" => raw_path.to_s,
      "raw_sha256" => Digest::SHA256.file(raw_path).hexdigest,
      "error" => nil
    }
  rescue StandardError => error
    {
      "canonical_id" => row.fetch("canonical_id"),
      "official_name" => official_name(row),
      "profile_url" => row["website_url"],
      "official_website_url" => nil,
      "external_candidates" => [],
      "raw_path" => nil,
      "raw_sha256" => nil,
      "error" => "#{error.class}: #{error.message}"
    }
  end

  def profile_section(document)
    document.css("section").find do |section|
      section.at_css("a[href^='mailto:']") && section.at_css("a[href*='/directory/']")
    end || document.css("section").find { _1.at_css("a[href^='mailto:']") }
  end

  def external_links(node)
    node.css("a[href]").filter_map do |anchor|
      href = anchor["href"].to_s.strip
      next unless href.match?(%r{\Ahttps?://}i)

      uri = URI(href)
      host = uri.host.to_s.downcase.sub(/\Awww\./, "")
      next if host.empty? || host == DIRECTORY_HOST || host.end_with?(".#{DIRECTORY_HOST}")
      next if SOCIAL_HOSTS.any? { |social| host == social || host.end_with?(".#{social}") }

      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end.uniq
  end

  def choose_official_url(candidates, row)
    return candidates.first if candidates.length <= 1

    name_tokens = normalize(official_name(row)).split.reject { _1.length < 3 }
    candidates.max_by do |url|
      host = normalize(URI(url).host)
      name_tokens.count { host.include?(_1) } * 10 - URI(url).path.to_s.count("/")
    rescue URI::InvalidURIError
      -100
    end
  end

  def directory_profile?(url)
    uri = URI(url.to_s)
    uri.host.to_s.downcase.sub(/\Awww\./, "") == DIRECTORY_HOST && uri.path.start_with?("/town/")
  rescue URI::InvalidURIError
    false
  end

  def update_coverage!(manifest, rows)
    incorporated = rows.reject { _1["municipality_type"] == "local_service_district" }
    standalone = incorporated.count { !directory_profile?(_1["website_url"]) }
    profiles = incorporated.count { directory_profile?(_1["website_url"]) }
    coverage = manifest.fetch("coverage").find { _1["subject"] == "websites" }
    return unless coverage

    coverage["status"] = standalone + profiles == incorporated.length ? "complete" : "partial"
    coverage["notes"] = "#{standalone} of #{incorporated.length} incorporated municipalities have a standalone " \
      "website linked from an upstream directory profile; #{profiles} retain an institution-specific directory profile."
  end

  def fetch(url, redirects: 6)
    raise "too many redirects for #{url}" if redirects.zero?

    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 20, read_timeout: 60) do |http|
      http.request(request)
    end
    if response.is_a?(Net::HTTPRedirection)
      return fetch(URI.join(uri, response["location"]).to_s, redirects: redirects - 1)
    end
    raise "HTTP #{response.code} for #{url}" unless response.code.to_i.between?(200, 299)

    response.body
  end

  def official_name(row)
    row["official_name_en"] || row["official_name_fr"] || row.fetch("official_name")
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def parallel_map(rows)
    queue = Queue.new
    rows.each_with_index { |row, index| queue << [ index, row ] }
    results = Array.new(rows.length)
    Array.new(@threads) do
      Thread.new do
        loop do
          index, row = queue.pop(true)
          results[index] = yield(row)
        rescue ThreadError
          break
        end
      end
    end.each(&:join)
    results
  end

  def write_json(path, payload)
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(payload) << "\n")
  end
end

options = { threads: 8 }
OptionParser.new do |parser|
  parser.banner = "Usage: backfill_newfoundland_municipal_websites.rb --manifest PATH --output PATH --audit PATH --raw-dir PATH --retrieved-at ISO8601"
  parser.on("--manifest PATH") { options[:manifest_path] = _1 }
  parser.on("--output PATH") { options[:output_path] = _1 }
  parser.on("--audit PATH") { options[:audit_path] = _1 }
  parser.on("--raw-dir PATH") { options[:raw_dir] = _1 }
  parser.on("--retrieved-at TIME") { options[:retrieved_at] = _1 }
  parser.on("--threads N", Integer) { options[:threads] = _1 }
end.parse!

missing = %i[manifest_path output_path audit_path raw_dir retrieved_at].reject { options[_1] }
abort "missing options: #{missing.join(', ')}" if missing.any?

BackfillNewfoundlandMunicipalWebsites.new(**options).run
