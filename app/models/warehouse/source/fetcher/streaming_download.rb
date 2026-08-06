# Streams large public data files into a temporary file while calculating the
# checksum. Spending disclosure dumps can be multiple gigabytes, so buffering
# an entire response in the job process is not viable.
class Warehouse::Source::Fetcher::StreamingDownload
  Result = Data.define(:io, :checksum)

  def initialize(url, http: HTTPX.plugin(:stream).plugin(:follow_redirects))
    @url = url
    @http = http
  end

  def call
    file = Tempfile.new([ "warehouse-source", File.extname(URI.parse(@url).path) ])
    file.binmode
    digest = Digest::SHA256.new

    response = @http.get(@url, stream: true)
    raise "HTTP #{response.status}: #{@url}" unless response.status == 200

    trailing_carriage_return = false
    response.each do |chunk|
      bytes = trailing_carriage_return ? "\r".b + chunk.b : chunk.b
      trailing_carriage_return = bytes.end_with?("\r".b)
      bytes = bytes.byteslice(0...-1) if trailing_carriage_return
      normalized = bytes.gsub("\r\n".b, "\n".b)
      digest.update(normalized)
      file.write(normalized)
    end
    if trailing_carriage_return
      digest.update("\r".b)
      file.write("\r".b)
    end
    raise "Empty response: #{@url}" if file.size.zero?

    file.rewind

    Result.new(io: file, checksum: digest.hexdigest)
  rescue
    file&.close!
    raise
  end
end
