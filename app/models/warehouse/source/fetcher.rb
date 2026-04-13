class Warehouse::Source::Fetcher < ActiveRecord::AssociatedObject
  performs :fetch

  MAX_RETRIES = 3
  BACKOFF_BASE = 4 # seconds: 1, 4, 16

  def fetch
    body = download_with_retries
    checksum = Digest::SHA256.hexdigest(body)

    if source.raw_ingestions.exists?(checksum: checksum)
      Rails.logger.info "[Fetcher] Source #{source.name}: data unchanged (checksum match), skipping"
      return
    end

    r2_key = "raw/#{source.name}/#{Date.current.iso8601}/#{File.basename(URI.parse(source.url).path)}"
    store_raw_file(r2_key, body)

    ingestion = source.raw_ingestions.create!(
      fetched_at: Time.current,
      raw_file_path: r2_key,
      checksum: checksum,
      status: :pending
    )

    source.update!(last_fetched_at: Time.current)

    dispatch_loader(ingestion, body)

    Rails.logger.info "[Fetcher] Source #{source.name}: ingestion #{ingestion.id} created"
  end

  private

  def download_with_retries
    retries = 0
    begin
      response = HTTPX.plugin(:follow_redirects).with(
        headers: {
          "user-agent" => "Mozilla/5.0 (compatible; BuildCanada/1.0; +https://buildcanada.com)",
          "accept" => "*/*"
        }
      ).get(source.url)
      raise "HTTP #{response.status}: #{source.url}" unless response.status == 200
      response.body.to_s
    rescue => e
      retries += 1
      if retries <= MAX_RETRIES
        sleep(BACKOFF_BASE ** (retries - 1))
        retry
      end
      raise "Failed to fetch #{source.url} after #{MAX_RETRIES} retries: #{e.message}"
    end
  end

  def store_raw_file(key, body)
    if r2_configured?
      R2Storage.new.upload(key: key, body: body)
    else
      local_path = Rails.root.join("storage", "raw", key)
      FileUtils.mkdir_p(File.dirname(local_path))
      File.binwrite(local_path, body)
      Rails.logger.info "[Fetcher] Stored locally: #{local_path}"
    end
  end

  def r2_configured?
    Rails.application.credentials.r2.present?
  rescue NoMethodError
    false
  end

  def dispatch_loader(ingestion, body)
    case source.name
    when /^infobase/
      ingestion.infobase_loader.load(csv_content: body)
    when /^estimates/
      ingestion.estimates_normalizer.normalize(csv_content: body)
    when /^lobbying/
      ingestion.lobbying_normalizer.normalize(csv_content: body)
    when /^statcan_boundary/, /^elections_canada/, /^ped_/, /^ward_/, /^sbw_/
      ingestion.boundary_loader.load(file_content: body)
    when /^statcan_geo_relationship/
      ingestion.relationship_loader.load(csv_content: body)
    when /^statcan_da_population/
      ingestion.population_loader.load(csv_content: body)
    when /^oda_/
      ingestion.address_loader.load(file_content: body)
    else
      Rails.logger.warn "[Fetcher] No loader configured for source: #{source.name}"
    end
  end
end
