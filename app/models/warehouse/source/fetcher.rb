class Warehouse::Source::Fetcher < ActiveRecord::AssociatedObject
  performs :fetch, queue_as: :scraping

  MAX_RETRIES = 3
  BACKOFF_BASE = 4 # seconds: 1, 4, 16

  def fetch
    with_retries do
      strategy.each_download do |download|
        begin
          process_download(download)
        ensure
          download.close
        end
      end
    end
    source.update!(last_fetched_at: Time.current)
  end

  private

  def strategy
    Warehouse::Source::Fetcher::Registry.for(source)
  end

  def process_download(download)
    existing = source.raw_ingestions.find_by(checksum: download.checksum)
    if existing && !existing.failed?
      Rails.logger.info "[Fetcher] Source #{source.name}: data unchanged (checksum match), skipping"
      return
    end

    r2_key = "raw/#{source.name}/#{Date.current.iso8601}/#{filename(download)}"
    store_raw_file(r2_key, download.body)
    rewind_body(download.body)

    ingestion = existing || source.raw_ingestions.new(checksum: download.checksum)
    ingestion.update!(
      fetched_at: Time.current,
      raw_file_path: r2_key,
      status: :pending,
      error_message: nil
    )

    download.load(ingestion)

    Rails.logger.info "[Fetcher] Source #{source.name}: ingestion #{ingestion.id} #{existing ? "retried" : "created"}"
  end

  def filename(download)
    download.filename.presence || File.basename(URI.parse(source.url).path).presence || "data.#{source.format}"
  end

  def with_retries
    retries = 0
    begin
      yield
    rescue => error
      retries += 1
      if retries <= MAX_RETRIES
        sleep(BACKOFF_BASE ** (retries - 1))
        retry
      end
      raise "Failed to fetch #{source.url} after #{MAX_RETRIES} retries: #{error.message}"
    end
  end

  def store_raw_file(key, body)
    if r2_configured?
      R2Storage.new.upload(key:, body:)
    else
      local_path = Rails.root.join("storage", "raw", key)
      FileUtils.mkdir_p(File.dirname(local_path))
      if body.respond_to?(:read)
        File.open(local_path, "wb") { |file| IO.copy_stream(body, file) }
      else
        File.binwrite(local_path, body)
      end
      Rails.logger.info "[Fetcher] Stored locally: #{local_path}"
    end
  end

  def rewind_body(body)
    return unless body.respond_to?(:rewind)

    body.rewind
    return unless body.respond_to?(:set_encoding) && body.respond_to?(:read)

    prefix = body.read(3)
    body.rewind
    body.pos = 3 if prefix&.b == "\xEF\xBB\xBF".b && body.respond_to?(:pos=)
    body.set_encoding(Encoding::UTF_8)
  end

  def r2_configured?
    Rails.application.credentials.r2.present?
  rescue NoMethodError
    false
  end
end
