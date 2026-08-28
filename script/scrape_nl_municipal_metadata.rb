#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "optparse"
require "set"
require "thread"
require "time"
require "uri"

class NlMunicipalMetadataScraper
  USER_AGENT = "YorkFactory public-government-data crawler; contact data@buildcanada.com"
  DIRECTORY_URL = "https://municipalnl.ca/directory/"
  API_URL = "https://municipalnl.ca/wp-json/wp/v2/town?per_page=100&page=%d"
  GENERATED_AT = "2026-08-24T12:00:00Z"
  GENERIC_EMAIL_DOMAINS = Set.new(%w[
    bellaliant.com bellaliant.net bellnet.ca eastlink.ca gmail.com hotmail.ca
    hotmail.com icloud.com live.ca live.com me.com msn.com netscape.net
    nf.aibn.com nl.rogers.com outlook.com persona.ca personainternet.com
    rogers.com sympatico.ca yahoo.ca yahoo.com
  ]).freeze
  SOCIAL_HOSTS = Set.new(%w[
    facebook.com instagram.com linkedin.com twitter.com x.com youtube.com
    www.facebook.com www.instagram.com www.linkedin.com www.twitter.com
    www.youtube.com
  ]).freeze

  def initialize(output_dir:, output_name: "municipal-metadata.json", threads: 8)
    @output_dir = File.expand_path(output_dir)
    @raw_dir = File.join(@output_dir, "raw")
    @profiles_dir = File.join(@raw_dir, "profiles")
    @homepages_dir = File.join(@raw_dir, "verified-homepages")
    @threads = threads
    @output_name = output_name
    @errors = []
    @errors_lock = Mutex.new
  end

  def run
    FileUtils.mkdir_p([ @profiles_dir, @homepages_dir ])
    towns = fetch_town_index
    download_profiles(towns)
    records = towns.map { |town| extract_record(town) }.sort_by { |record| record.fetch("name") }
    verify_candidate_websites(records)
    write_outputs(records)
  end

  private

  def fetch_town_index
    towns = []
    page = 1

    loop do
      path = File.join(@raw_dir, "wp-towns-page-#{page}.json")
      body = File.exist?(path) ? File.binread(path) : fetch!(format(API_URL, page)).fetch(:body)
      write_new(path, body) unless File.exist?(path)
      batch = JSON.parse(body)
      break if batch.empty?

      towns.concat(batch)
      break if batch.length < 100

      page += 1
    end

    towns
  end

  def download_profiles(towns)
    queue = Queue.new
    towns.each { |town| queue << town }

    Array.new(@threads) do
      Thread.new do
        loop do
          town = queue.pop(true)
          path = profile_path(town)
          next if File.exist?(path)

          response = fetch!(town.fetch("link"))
          write_new(path, response.fetch(:body))
        rescue ThreadError
          break
        rescue StandardError => error
          record_error("profile", town&.dig("slug"), error)
        end
      end
    end.each(&:join)
  end

  def extract_record(town)
    path = profile_path(town)
    document = File.exist?(path) ? Nokogiri::HTML(File.binread(path)) : nil
    emails = document ? extract_emails(document) : []
    external_links = document ? extract_external_links(document) : []
    contact_text = document ? extract_contact_text(document) : nil

    {
      "directory_id" => town.fetch("id"),
      "name" => CGI.unescapeHTML(town.dig("title", "rendered").to_s),
      "slug" => town.fetch("slug"),
      "profile_url" => town.fetch("link"),
      "profile_modified_at" => town["modified_gmt"],
      "profile_sha256" => File.exist?(path) ? Digest::SHA256.file(path).hexdigest : nil,
      "emails" => emails,
      "phones" => contact_text.to_s.scan(/(?:\+?1[ .-]?)?\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}/).uniq,
      "contact_text" => contact_text,
      "external_links" => external_links,
      "website_candidates" => website_candidates(external_links, emails),
      "website_url" => nil,
      "website_status" => "not_verified"
    }
  end

  def extract_emails(document)
    document.css('a[href^="mailto:"]').filter_map do |link|
      link["href"].delete_prefix("mailto:").split(/[?;]/).first&.strip&.downcase
    end.uniq.sort
  end

  def extract_external_links(document)
    document.css("a[href]").filter_map do |link|
      href = link["href"].to_s.strip
      next unless href.match?(%r{\Ahttps?://}i)

      uri = URI.parse(href)
      next if uri.host.nil? || uri.host.end_with?("municipalnl.ca") || SOCIAL_HOSTS.include?(uri.host.downcase)

      href
    rescue URI::InvalidURIError
      nil
    end.uniq.sort
  end

  def extract_contact_text(document)
    heading = document.xpath("//*[self::h1 or self::h2 or self::h3 or self::h4 or self::h5 or self::h6][contains(translate(normalize-space(.), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), 'contact information')]").first
    return nil unless heading

    container = heading.parent
    text = container.text.gsub(/\s+/, " ").strip
    text.empty? ? nil : text
  end

  def website_candidates(external_links, emails)
    candidates = external_links.map { |url| { "url" => url, "method" => "profile_external_link" } }
    emails.each do |email|
      domain = email.split("@").last
      next if domain.nil? || GENERIC_EMAIL_DOMAINS.include?(domain)

      candidates << { "url" => "https://#{domain}/", "method" => "contact_email_domain" }
    end
    candidates.uniq { |candidate| candidate.fetch("url") }
  end

  def verify_candidate_websites(records)
    queue = Queue.new
    records.each { |record| queue << record }

    Array.new(@threads) do
      Thread.new do
        loop do
          record = queue.pop(true)
          verify_record_website(record)
        rescue ThreadError
          break
        rescue StandardError => error
          record_error("website", record&.dig("slug"), error)
        end
      end
    end.each(&:join)
  end

  def verify_record_website(record)
    record.fetch("website_candidates").each do |candidate|
      response = fetch_candidate!(candidate)
      next unless response.fetch(:status).between?(200, 299)
      next unless page_matches_name?(response.fetch(:body), record.fetch("name"))

      record["website_url"] = response.fetch(:url)
      record["website_status"] = "verified"
      record["website_verification_method"] = candidate.fetch("method")
      record["website_verified_at"] = GENERATED_AT
      homepage_path = File.join(@homepages_dir, "#{record.fetch('slug')}.html")
      write_new(homepage_path, response.fetch(:body)) unless File.exist?(homepage_path)
      record["website_homepage_sha256"] = Digest::SHA256.file(homepage_path).hexdigest
      return
    rescue StandardError => error
      candidate["error"] = "#{error.class}: #{error.message}"
    end
  end

  def fetch_candidate!(candidate)
    url = candidate.fetch("url")
    fetch!(url, limit: 8)
  rescue StandardError => https_error
    raise unless candidate.fetch("method") == "contact_email_domain" && url.start_with?("https://")

    begin
      fetch!(url.sub("https://", "http://"), limit: 8)
    rescue StandardError => http_error
      raise "HTTPS: #{https_error.message}; HTTP: #{http_error.message}"
    end
  end

  def page_matches_name?(body, name)
    document = Nokogiri::HTML(body)
    haystack = normalize([ document.at_css("title")&.text, document.at_css("h1")&.text, document.at_css("body")&.text&.slice(0, 25_000) ].compact.join(" "))
    needle = normalize(name)
    return true if haystack.include?(needle)

    tokens = needle.split.reject { |token| token.length < 3 || %w[and beach bay city cove harbour island point river town].include?(token) }
    tokens.any? && tokens.all? { |token| haystack.include?(token) }
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "").downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def profile_path(town)
    File.join(@profiles_dir, "#{town.fetch('slug')}.html")
  end

  def fetch!(url, limit: 6)
    raise "too many redirects for #{url}" if limit.zero?

    uri = URI.parse(url)
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = USER_AGENT
    request["Accept"] = "text/html,application/json;q=0.9,*/*;q=0.5"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 45) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPRedirection)
      return fetch!(URI.join(uri, response.fetch("location")).to_s, limit: limit - 1)
    end

    raise "HTTP #{response.code} for #{url}" unless response.code.to_i.between?(200, 299)

    { body: response.body, status: response.code.to_i, url: uri.to_s }
  end

  def write_outputs(records)
    payload = {
      "generated_at" => GENERATED_AT,
      "directory_url" => DIRECTORY_URL,
      "record_count" => records.length,
      "verified_website_count" => records.count { |record| record["website_status"] == "verified" },
      "email_count" => records.count { |record| record.fetch("emails").any? },
      "phone_count" => records.count { |record| record.fetch("phones").any? },
      "errors" => @errors.sort_by { |error| [ error.fetch("stage"), error.fetch("slug").to_s ] },
      "records" => records
    }
    output_path = File.join(@output_dir, @output_name)
    write_new(output_path, JSON.pretty_generate(payload) << "\n")
    puts JSON.pretty_generate(payload.slice("record_count", "verified_website_count", "email_count", "phone_count"))
    puts "output=#{output_path}"
    puts "sha256=#{Digest::SHA256.file(output_path).hexdigest}"
  end

  def write_new(path, content)
    raise "refusing to overwrite #{path}" if File.exist?(path)

    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
  end

  def record_error(stage, slug, error)
    @errors_lock.synchronize do
      @errors << { "stage" => stage, "slug" => slug, "error" => "#{error.class}: #{error.message}" }
    end
  end
end

options = { output_name: "municipal-metadata.json", threads: 8 }
OptionParser.new do |parser|
  parser.banner = "Usage: scrape_nl_municipal_metadata.rb --output-dir PATH [--threads N]"
  parser.on("--output-dir PATH") { |value| options[:output_dir] = value }
  parser.on("--output-name NAME") { |value| options[:output_name] = value }
  parser.on("--threads N", Integer) { |value| options[:threads] = value }
end.parse!

abort "--output-dir is required" unless options[:output_dir]

NlMunicipalMetadataScraper.new(**options).run
