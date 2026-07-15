class Warehouse::Source::Fetcher < ActiveRecord::AssociatedObject
  performs :fetch

  MAX_RETRIES = 3
  BACKOFF_BASE = 4 # seconds: 1, 4, 16

  def fetch
    body = download_body
    checksum = Digest::SHA256.hexdigest(body)

    # A checksum match only skips when the prior load got somewhere: pending
    # and partial may be in flight or awaiting review, and re-dispatching
    # could double-run them. A failed ingestion is retried on the same row
    # (checksum is unique per source), so a load crash can't wedge the source
    # until its upstream data changes.
    existing = source.raw_ingestions.find_by(checksum: checksum)
    if existing && !existing.failed?
      Rails.logger.info "[Fetcher] Source #{source.name}: data unchanged (checksum match), skipping"
      return
    end

    filename = File.basename(URI.parse(source.url).path).presence || "data.#{source.format}"
    r2_key = "raw/#{source.name}/#{Date.current.iso8601}/#{filename}"
    store_raw_file(r2_key, body)

    ingestion = existing || source.raw_ingestions.new(checksum: checksum)
    ingestion.update!(
      fetched_at: Time.current,
      raw_file_path: r2_key,
      status: :pending,
      error_message: nil
    )

    source.update!(last_fetched_at: Time.current)

    dispatch_loader(ingestion, body)

    Rails.logger.info "[Fetcher] Source #{source.name}: ingestion #{ingestion.id} #{existing ? "retried" : "created"}"
  end

  private

  # API-style sources (paginated JSON, multi-step downloads) normalize their
  # payload to a single canonical body at fetch time, so checksum dedupe and
  # the R2 archive operate on exactly what the loader parses.
  def download_body
    case source.format
    when "worldbank_json"
      with_retries { Warehouse::Source::Fetcher::WorldBankDownload.new(source.url).call }
    when "statcan_json"
      with_retries { Warehouse::Source::Fetcher::StatcanVectors.new(source.url).call }
    else
      download_with_retries
    end
  end

  def download_with_retries
    with_retries do
      response = HTTPX.plugin(:follow_redirects).get(source.url)
      raise "HTTP #{response.status}: #{source.url}" unless response.status == 200
      response.body.to_s
    end
  end

  def with_retries
    retries = 0
    begin
      yield
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
    when /^econ_worldbank/
      ingestion.world_bank_econ_loader.load(json_content: body)
    when /^econ_oecd/
      ingestion.oecd_sdmx_loader.load(csv_content: body)
    when /^econ_statcan/
      ingestion.statcan_econ_loader.load(json_content: body)
    when /^econ_ircc/
      ingestion.ircc_admissions_loader.load(csv_content: body)
    when /^econ_owid/
      ingestion.owid_econ_loader.load(csv_content: body)
    else
      Rails.logger.warn "[Fetcher] No loader configured for source: #{source.name}"
    end
  end
end
