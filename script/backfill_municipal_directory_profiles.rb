#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "optparse"
require "pathname"
require "uri"

class BackfillMunicipalDirectoryProfiles
  USER_AGENT = "YorkFactory public-government-data crawler; contact data@buildcanada.com"
  SK_DIRECTORY = "https://www.saskatchewan.ca/government/municipal-administration/municipal-directory"
  NL_DIRECTORY = "https://municipalnl.ca/directory/"
  NL_API = "https://municipalnl.ca/wp-json/wp/v2/town"
  PE_DIRECTORY = "https://www.princeedwardisland.ca/en/feature/municipal-directory"

  def initialize(manifest_path:, output_path:, raw_dir:)
    @manifest_path = Pathname(manifest_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @raw_dir = Pathname(raw_dir).expand_path
  end

  def run
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    code = manifest.fetch("province").fetch("code")
    FileUtils.mkdir_p(@raw_dir)
    profiles, source_url, status = case code
    when "sk" then [ saskatchewan_profiles, SK_DIRECTORY, "verified_official_directory_profile" ]
    when "nl" then [ newfoundland_profiles, NL_DIRECTORY, "verified_association_directory_profile" ]
    when "pe" then [ {}, PE_DIRECTORY, "verified_official_directory_listing" ]
    else raise "unsupported province #{code}"
    end

    matched = 0
    unresolved = []
    manifest.fetch("municipalities").each do |row|
      next if row["website_url"].to_s.start_with?("http")
      next if code == "nl" && row["municipality_type"] == "local_service_district"

      profile_url = profiles[normalize(display_name(row))]
      profile_url ||= PE_DIRECTORY if code == "pe"
      if profile_url
        row["website_url"] = profile_url
        row["website_source_url"] = source_url
        row["website_status"] = status
        row["website_gap"] = nil
        matched += 1
      else
        unresolved << row.fetch("canonical_id")
      end
    end
    update_coverage(manifest, code)
    manifest["directory_profile_backfill"] = {
      "source_url" => source_url,
      "raw_directory" => @raw_dir.to_s,
      "matched_missing_websites" => matched,
      "unresolved" => unresolved
    }
    @output_path.write(JSON.pretty_generate(manifest) << "\n")
    puts JSON.pretty_generate(
      province: code,
      matched_missing_websites: matched,
      unresolved: unresolved.length,
      institutions_with_web_presence: manifest.fetch("municipalities").count { _1["website_url"].to_s.start_with?("http") },
      output: @output_path.to_s,
      sha256: Digest::SHA256.file(@output_path).hexdigest
    )
  end

  private

  def saskatchewan_profiles
    root = fetch(SK_DIRECTORY)
    archive("sk-directory.html", root)
    document = Nokogiri::HTML(root)
    category_urls = document.css("a[href*='municipal-directory?c=']").map { absolute_url(_1["href"], SK_DIRECTORY) }.uniq
    category_urls.each_with_object({}).with_index do |(url, profiles), index|
      html = fetch(url)
      archive("sk-directory-category-#{index + 1}.html", html)
      Nokogiri::HTML(html).css("a[href*='municipal-directory?s=']").each do |anchor|
        profiles[normalize(anchor.text)] = absolute_url(anchor["href"], SK_DIRECTORY)
      end
    end
  end

  def newfoundland_profiles
    (1..3).each_with_object({}) do |page, profiles|
      url = "#{NL_API}?per_page=100&page=#{page}&_fields=slug,link,title"
      json = fetch(url)
      archive("nl-town-api-page-#{page}.json", json)
      JSON.parse(json).each do |row|
        name = Nokogiri::HTML.fragment(row.fetch("title").fetch("rendered")).text
        profiles[normalize(name)] = row.fetch("link")
      end
    end
  end

  def update_coverage(manifest, code)
    rows = manifest.fetch("municipalities")
    scoped = code == "nl" ? rows.reject { _1["municipality_type"] == "local_service_district" } : rows
    with_web = scoped.count { _1["website_url"].to_s.start_with?("http") }
    coverage = manifest.fetch("coverage").find { _1["subject"] == "websites" }
    return unless coverage

    coverage["status"] = with_web == scoped.length ? "complete" : "partial"
    coverage["notes"] = "#{with_web} of #{scoped.length} municipalities have a standalone official website or an institution-specific public directory profile."
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

  def archive(name, body)
    @raw_dir.join(name).binwrite(body)
  end

  def absolute_url(value, base)
    URI.join(base, CGI.unescapeHTML(value)).to_s
  end

  def display_name(row)
    row["official_name_en"] || row["official_name_fr"] || row.fetch("official_name")
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase.gsub(/\b(?:rural municipality|resort village|northern town|northern village|northern hamlet|city|town|village) of\b/, " ")
      .gsub(/[^a-z0-9]+/, " ").strip
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: backfill_municipal_directory_profiles.rb --manifest PATH --output PATH --raw-dir PATH"
  parser.on("--manifest PATH") { options[:manifest_path] = _1 }
  parser.on("--output PATH") { options[:output_path] = _1 }
  parser.on("--raw-dir PATH") { options[:raw_dir] = _1 }
end.parse!

missing = %i[manifest_path output_path raw_dir].reject { options[_1] }
abort "missing options: #{missing.join(', ')}" if missing.any?

BackfillMunicipalDirectoryProfiles.new(**options).run
