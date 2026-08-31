#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "optparse"
require "pathname"
require "time"
require "uri"

class EnrichNbLocalGovernmentManifest
  UMNB_URL = "https://umnb.ca/umnb-members/"
  AFMNB_URL = "https://www.afmnb.org/municipalit%C3%A9s-membres"
  RURAL_DISTRICTS_URL = "https://www.gnb.ca/en/topic/family-home-community/communty-local-gov/rural-districts.html"
  USER_AGENT = "YorkFactory public-government-data crawler; contact data@buildcanada.com"
  SPECIAL_WEBSITES = {
    "ca/nb/five-rivers" => "https://5-rivers.ca/",
    "ca/nb/grand-bouctouche" => "https://villedebouctouche.ca/en/",
    "ca/nb/grand-manan" => "https://www.villageofgrandmanan.com/",
    "ca/nb/kedgwick" => "https://www.kedgwicknb.com/",
    "ca/nb/nouvelle-arcadie" => "https://rogersvillenb.com/",
    "ca/nb/saint-andrews" => "https://www.townofsaintandrews.ca/",
    "ca/nb/sunbury-york-south" => "https://sysrc.ca/home/",
    "ca/nb/sussex" => "https://sussex.ca/",
    "ca/nb/tracy" => "https://www.villageoftracy.com/",
    "ca/nb/upper-miramichi" => "https://uppermiramichi.ca/"
  }.freeze
  NAME_ALIASES = {
    "campobello" => "campobello island",
    "grand falls" => "grand sault",
    "grand bouctouch" => "grand bouctouche",
    "york sunbury south" => "sunbury york south"
  }.freeze

  def initialize(input:, output:, raw_dir:, effective_on:, published_at:)
    @input = Pathname(input).expand_path
    @output = Pathname(output).expand_path
    @raw_dir = Pathname(raw_dir).expand_path
    @effective_on = effective_on
    @published_at = Time.iso8601(published_at).utc.iso8601
  end

  def run
    raise "refusing to overwrite #{@output}" if @output.exist?

    FileUtils.mkdir_p(@raw_dir)
    sources = {
      "umnb" => archive_source("umnb-members.html", UMNB_URL),
      "afmnb" => archive_source("afmnb-members.html", AFMNB_URL),
      "rural_districts" => archive_source("gnb-rural-districts.html", RURAL_DISTRICTS_URL)
    }
    umnb = parse_umnb(sources.fetch("umnb").fetch("body"))
    afmnb = parse_afmnb(sources.fetch("afmnb").fetch("body"))
    manifest = JSON.parse(@input.read)
    rows = manifest.fetch("municipalities")

    rows.each do |row|
      enrich_row(row, umnb, afmnb)
    end
    missing = rows.reject { |row| row["website_url"] }
    raise "missing official pages for #{missing.map { |row| row.fetch('canonical_id') }.join(', ')}" if missing.any?

    manifest["release_version"] = @effective_on
    manifest["effective_on"] = @effective_on
    manifest["published_at"] = @published_at
    manifest["derived_from_release_manifest"] = @input.to_s
    manifest["metadata_sources"] = sources.transform_values { |source| source.except("body") }
    update_coverage(manifest, rows)
    manifest["scrape_gaps"] = [
      "Financial statements and annual reports require crawling the enriched official pages.",
      "New Brunswick rural districts share a provincial official information page because the province coordinates their services through rural district managers."
    ]
    @output.dirname.mkpath
    @output.write(JSON.pretty_generate(manifest) << "\n")
    puts JSON.pretty_generate(
      "institutions" => rows.length,
      "websites" => rows.count { |row| row["website_url"] },
      "contacts" => rows.count { |row| row["contact"] },
      "output" => @output.to_s,
      "sha256" => Digest::SHA256.file(@output).hexdigest
    )
  end

  private

  def archive_source(filename, url)
    body, resolved_url = fetch(url)
    path = @raw_dir.join(filename)
    path.write(body)
    {
      "url" => resolved_url,
      "retrieved_at" => @published_at,
      "archive_path" => path.to_s,
      "content_sha256" => Digest::SHA256.hexdigest(body),
      "body" => body
    }
  end

  def fetch(url, redirects: 5)
    raise "too many redirects for #{url}" if redirects.negative?

    uri = URI(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "text/html,application/xhtml+xml"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 45) do |http|
      http.request(request)
    end
    return fetch(URI.join(url, response.fetch("location")).to_s, redirects: redirects - 1) if response.is_a?(Net::HTTPRedirection)
    raise "#{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    [ response.body, url ]
  end

  def parse_umnb(html)
    Nokogiri::HTML(html).css("a[href]").each_with_object({}) do |anchor, found|
      url = anchor["href"].to_s.strip
      next unless url.match?(%r{\Ahttps?://})
      next if URI(url.gsub(" ", "%20")).host.to_s.end_with?("umnb.ca")

      name = normalize(anchor.text)
      name = NAME_ALIASES.fetch(name, name)
      next if name.empty?

      found[name] = url.strip.gsub(/%20\z/, "")
    rescue URI::InvalidURIError
      next
    end
  end

  def parse_afmnb(html)
    marker = /"municipalites":"/
    starts = html.enum_for(:scan, marker).map { Regexp.last_match.begin(0) }
    starts.each_with_index.each_with_object({}) do |(start, index), found|
      segment = html.byteslice(start, (starts[index + 1] || html.bytesize) - start)
      name = json_string(segment[/\A"municipalites":("(?:\\.|[^"])*")/, 1])
      next unless name

      record = {
        "website_url" => json_string(segment[/"siteWeb":("(?:\\.|[^"])*")/, 1]),
        "email" => json_string(segment[/"courriel":("(?:\\.|[^"])*")/, 1]),
        "phone" => json_string(segment[/"telephone":("(?:\\.|[^"])*")/, 1]),
        "mailing_address" => json_string(segment[/"formatted":("(?:\\.|[^"])*")/, 1])
      }.compact
      found[normalize(name)] = record if record.any?
    end
  end

  def json_string(encoded)
    JSON.parse(encoded) if encoded
  rescue JSON::ParserError
    nil
  end

  def enrich_row(row, umnb, afmnb)
    id = row.fetch("canonical_id")
    if row.fetch("municipality_type") == "rural_district"
      row["website_url"] = RURAL_DISTRICTS_URL
      row["website_source_url"] = RURAL_DISTRICTS_URL
      row["website_status"] = "verified_upstream"
      row["scrape_gaps"] = [ "This rural district uses the province-wide official rural-district information page." ]
      return
    end

    key = normalize(row.fetch("official_name_en"))
    association_record = afmnb[key] || {}
    website = SPECIAL_WEBSITES[id] || association_record["website_url"] || umnb[key]
    raise "no website found for #{id}" unless website

    source = association_record["website_url"] == website ? AFMNB_URL : UMNB_URL
    source = UMNB_URL if SPECIAL_WEBSITES.key?(id) && umnb.value?(website)
    source = AFMNB_URL if SPECIAL_WEBSITES.key?(id) && association_record["website_url"] == website
    source = website if %w[ca/nb/tracy ca/nb/upper-miramichi].include?(id)
    row["website_url"] = strip_tracking(website)
    row["website_source_url"] = source
    row["website_status"] = "verified_upstream"
    row["scrape_gaps"] = []
    contact = association_record.slice("email", "phone", "mailing_address")
    row["contact"] = contact if contact.any?
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def strip_tracking(url)
    uri = URI(url)
    return url unless uri.query

    retained = URI.decode_www_form(uri.query).reject { |key, _value| key.start_with?("utm_") || key == "fbclid" }
    uri.query = retained.any? ? URI.encode_www_form(retained) : nil
    uri.to_s
  rescue URI::InvalidURIError
    url
  end

  def update_coverage(manifest, rows)
    websites = manifest.fetch("coverage").find { |row| row["subject"] == "websites" }
    websites["status"] = "complete"
    websites["notes"] = "#{rows.count { |row| row['website_url'] }} of #{rows.length} institutions have an official website or official institution-specific government information page."
    websites["source_url"] = UMNB_URL
    financials = manifest.fetch("coverage").find { |row| row["subject"] == "financial-statements" }
    financials["status"] = "not-searched"
    financials["notes"] = "Official websites were enriched but financial-report crawling is pending."
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: enrich_nb_local_government_manifest.rb --input PATH --output PATH --raw-dir PATH --effective-on DATE --published-at ISO8601"
  parser.on("--input PATH") { |value| options[:input] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
  parser.on("--raw-dir PATH") { |value| options[:raw_dir] = value }
  parser.on("--effective-on DATE") { |value| options[:effective_on] = value }
  parser.on("--published-at ISO8601") { |value| options[:published_at] = value }
end.parse!

missing = %i[input output raw_dir effective_on published_at].reject { |key| options[key] }
abort "missing options: #{missing.join(', ')}" if missing.any?

EnrichNbLocalGovernmentManifest.new(**options).run
