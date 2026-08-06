class Warehouse::Source::Fetcher::Download
  attr_reader :body, :checksum, :filename

  def initialize(body:, checksum:, filename: nil, &loader)
    @body = body
    @checksum = checksum
    @filename = filename
    @loader = loader
  end

  def load(ingestion)
    @loader.call(ingestion, body)
  end

  def close
    return unless body.respond_to?(:close)

    body.respond_to?(:close!) ? body.close! : body.close
  end
end
