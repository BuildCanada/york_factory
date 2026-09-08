#!/usr/bin/env ruby

require "csv"
require "date"
require "json"
require "net/http"
require "optparse"
require "securerandom"
require "uri"

ACCOUNTS = %w[build_canada build_toronto canada_spends lucyhargreaves4].freeze
REQUIRED_HEADERS = [
  "Date", "Impressions", "Likes", "Engagements", "Bookmarks", "Shares",
  "New follows", "Unfollows", "Replies", "Reposts", "Profile visits",
  "Create Post", "Video views", "Media views"
].freeze

begin
options = {
  base_url: ENV.fetch("YORK_FACTORY_URL", "https://yorkfactory.buildcanada.com"),
  dry_run: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: upload_x_csv.rb --account ACCOUNT --file PATH [options]"
  parser.on("--account ACCOUNT", ACCOUNTS, "York Factory account key") { |value| options[:account] = value }
  parser.on("--file PATH", "Downloaded X analytics CSV") { |value| options[:file] = value }
  parser.on("--base-url URL", "York Factory base URL") { |value| options[:base_url] = value }
  parser.on("--dry-run", "Validate without uploading") { options[:dry_run] = true }
end.parse!

abort "Missing --account (#{ACCOUNTS.join(', ')})" unless options[:account]
abort "Missing --file" unless options[:file]

path = File.expand_path(options[:file])
abort "CSV does not exist: #{path}" unless File.file?(path)
abort "Expected a .csv file: #{path}" unless File.extname(path).downcase == ".csv"

table = CSV.read(path, headers: true, encoding: "bom|utf-8")
missing_headers = REQUIRED_HEADERS - table.headers.compact
abort "Invalid X analytics CSV; missing headers: #{missing_headers.join(', ')}" if missing_headers.any?
abort "Invalid X analytics CSV; no data rows" if table.empty?

dates = table.filter_map do |row|
  value = row["Date"]
  Date.parse(value) if value && !value.empty?
rescue Date::Error
  abort "Invalid X analytics CSV date: #{value.inspect}"
end
abort "Invalid X analytics CSV; no dates" if dates.empty?

validation = {
  account: options[:account],
  file: path,
  rows: table.length,
  first_date: dates.min.iso8601,
  last_date: dates.max.iso8601
}

if options[:dry_run]
  puts JSON.generate(validation.merge(valid: true, uploaded: false))
  exit 0
end

token = ENV["YORK_FACTORY_API_KEY"].to_s
abort "Missing YORK_FACTORY_API_KEY" if token.empty?

base_uri = URI.parse(options[:base_url])
abort "YORK_FACTORY_URL must use HTTP(S)" unless base_uri.is_a?(URI::HTTP) && base_uri.host
uri = URI.join("#{options[:base_url].delete_suffix('/')}/", "api/v1/metrics/twitter_stats/import")

boundary = "----YorkFactory#{SecureRandom.hex(16)}"
csv_bytes = File.binread(path)
body = +"".b
body << "--#{boundary}\r\n".b
body << "Content-Disposition: form-data; name=\"account\"\r\n\r\n".b
body << options[:account].b << "\r\n".b
body << "--#{boundary}\r\n".b
body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(path)}\"\r\n".b
body << "Content-Type: text/csv\r\n\r\n".b
body << csv_bytes << "\r\n--#{boundary}--\r\n".b

request = Net::HTTP::Post.new(uri)
request["Accept"] = "application/json"
request["Authorization"] = "Bearer #{token}"
request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
request["User-Agent"] = "YorkFactoryXAnalyticsSkill/1.0"
request.body = body

response = Net::HTTP.start(
  uri.host,
  uri.port,
  use_ssl: uri.scheme == "https",
  open_timeout: 15,
  read_timeout: 60
) { |http| http.request(request) }

payload = JSON.parse(response.body)
unless response.is_a?(Net::HTTPSuccess)
  abort "Upload rejected (HTTP #{response.code}): #{payload['details'] || payload['error'] || response.message}"
end

puts JSON.generate(validation.merge(uploaded: true, response: payload))
rescue CSV::MalformedCSVError => error
  abort "Invalid X analytics CSV: #{error.message}"
rescue JSON::ParserError => error
  abort "York Factory returned invalid JSON: #{error.message}"
rescue URI::InvalidURIError => error
  abort "Invalid YORK_FACTORY_URL: #{error.message}"
rescue SystemCallError, Timeout::Error, SocketError => error
  abort "Upload failed: #{error.message}"
end
