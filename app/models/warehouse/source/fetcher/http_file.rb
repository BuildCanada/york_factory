class Warehouse::Source::Fetcher::HttpFile
  def initialize(url, streaming: false, http: nil, &loader)
    @url = url
    @streaming = streaming
    @http = http
    @loader = loader
  end

  def each_download
    return enum_for(__method__) unless block_given?

    if @streaming
      result = streaming_download.call
      yield download(result.io, result.checksum)
    else
      body = buffered_download
      yield download(body, Digest::SHA256.hexdigest(body))
    end
  end

  private

  def streaming_download
    options = { http: @http }.compact
    Warehouse::Source::Fetcher::StreamingDownload.new(@url, **options)
  end

  def buffered_download
    response = (@http || HTTPX.plugin(:follow_redirects)).get(@url)
    raise "HTTP #{response.status}: #{@url}" unless response.status == 200

    response.body.to_s
  end

  def download(body, checksum)
    loader = @loader
    Warehouse::Source::Fetcher::Download.new(body:, checksum:) do |ingestion, content|
      loader.call(ingestion, content)
    end
  end
end
