require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "stringio"
require "uri"
require "zip"

module Warehouse::InstitutionRelease::FirstNations
  class FinancialStatementArchiver
    class ArchiveError < StandardError; end

    DEFAULT_ASSET_ROOT = Pathname("/Volumes/floppy/york_factory/public_institutions/assets")

    attr_reader :inventory_path

    def initialize(manifest_path:, asset_root: DEFAULT_ASSET_ROOT, inventory_path: nil, http_client: nil,
      retrieved_at: Time.current, workers: 8)
      @manifest_path = Pathname(manifest_path)
      @asset_root = Pathname(asset_root).expand_path
      @requested_inventory_path = inventory_path && Pathname(inventory_path)
      @http = http_client || HttpClient.new
      @retrieved_at = retrieved_at.utc
      @workers = Integer(workers)
      raise ArgumentError, "workers must be positive" unless @workers.positive?
    end

    def call
      manifest = JSON.parse(@manifest_path.read)
      @inventory_path = @requested_inventory_path || @manifest_path.dirname.join("financial-statement-assets.json")
      raise ArchiveError, "asset inventory already exists: #{@inventory_path}" if @inventory_path.exist?
      @inventory_path.dirname.mkpath

      reports = manifest.fetch("bands").flat_map { |band| Array(band["reports"]) }
      assets = parallel_map(reports) { |report| archive(report) }
      @inventory_path.write(JSON.pretty_generate({
        release_version: manifest.fetch("release_version"), retrieved_at: @retrieved_at.iso8601,
        asset_root: @asset_root.to_s, assets: assets
      }) << "\n")
      @inventory_path
    rescue Errno::ENOENT, JSON::ParserError, KeyError => error
      raise ArchiveError, error.message
    end

    private

    def archive(report)
      response = @http.get(report.fetch("download_url"))
      bytes = response.respond_to?(:body) ? response.body : response.to_s
      raise ArchiveError, "empty FNFTA response for #{report.fetch('canonical_id')}" if bytes.empty?

      mime_type, extension = sniff(bytes, response.respond_to?(:content_type) ? response.content_type : nil)
      digest = Digest::SHA256.hexdigest(bytes)
      relative = Pathname("sha256").join(digest.first(2), "#{digest}.#{extension}")
      destination = @asset_root.join(relative)
      destination.dirname.mkpath
      if destination.exist?
        raise ArchiveError, "content-address collision at #{destination}" unless Digest::SHA256.file(destination).hexdigest == digest
      else
        temporary = destination.sub_ext("#{destination.extname}.tmp-#{Process.pid}")
        temporary.binwrite(bytes)
        FileUtils.mv(temporary, destination)
      end
      {
        document_canonical_id: report.fetch("canonical_id"), content_sha256: digest,
        asset_role: "final", preferred: true, download_url: report.fetch("download_url"),
        retrieved_at: @retrieved_at.iso8601, archive_path: relative.to_s,
        mime_type: mime_type, byte_size: bytes.bytesize, rights_status: "metadata_only"
      }
    rescue StandardError => error
      {
        document_canonical_id: report.fetch("canonical_id"), download_url: report.fetch("download_url"),
        retrieved_at: @retrieved_at.iso8601, error: error.message
      }
    end

    def sniff(bytes, header)
      bytes = bytes.b
      return [ "application/pdf", "pdf" ] if bytes.start_with?("%PDF-")
      if bytes.start_with?("PK\x03\x04".b)
        entries = Zip::File.open_buffer(StringIO.new(bytes)) { |archive| archive.entries.map(&:name) }
        return [ "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx" ] if entries.include?("word/document.xml")
        return [ "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx" ] if entries.include?("xl/workbook.xml")

        raise ArchiveError, "unrecognized OOXML financial statement package"
      end
      return [ "application/vnd.ms-excel", "xls" ] if bytes.start_with?("\xD0\xCF\x11\xE0".b)

      normalized = header.to_s.split(";").first
      raise ArchiveError, "FNFTA response was HTML, not a financial statement" if normalized == "text/html" || bytes.lstrip.start_with?("<")

      [ normalized.presence || "application/octet-stream", "bin" ]
    end

    def parallel_map(rows)
      queue = Queue.new
      rows.each_with_index { |row, index| queue << [ index, row ] }
      results = Array.new(rows.length)
      [ @workers, rows.length ].min.times.map do
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

    class HttpClient
      Response = Data.define(:body, :content_type)

      def initialize(max_attempts: 3, retry_delay: 1)
        @max_attempts = Integer(max_attempts)
        @retry_delay = Float(retry_delay)
      end

      def get(url, redirects: 5, attempts: nil)
        attempts ||= @max_attempts
        uri = URI(url)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = SourceAdapter::HttpClient::USER_AGENT
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: 20, read_timeout: 180) { |http| http.request(request) }
        return Response.new(body: response.body, content_type: response["content-type"]) if response.is_a?(Net::HTTPSuccess)
        if response.is_a?(Net::HTTPRedirection) && redirects.positive?
          return get(URI.join(uri, response.fetch("location")).to_s, redirects: redirects - 1)
        end

        if response.code.to_i == 429 || response.code.to_i >= 500
          raise ArchiveError, "transient HTTP #{response.code} for #{uri}"
        end
        raise ArchiveError, "HTTP #{response.code} for #{uri}"
      rescue Net::OpenTimeout, Net::ReadTimeout, EOFError, Errno::ECONNRESET, OpenSSL::SSL::SSLError, ArchiveError => error
        raise if attempts <= 1 || (error.is_a?(ArchiveError) && !error.message.start_with?("transient HTTP"))

        sleep(@retry_delay * (@max_attempts - attempts + 1))
        get(url, redirects: redirects, attempts: attempts - 1)
      end
    end
  end
end
