class Warehouse::Source::Fetcher < ActiveRecord::AssociatedObject
  performs :fetch

  MAX_RETRIES = 3
  BACKOFF_BASE = 4 # seconds: 1, 4, 16
  STREAMING_FORMATS = %w[
    spending_proactive_contracts_csv
    spending_aggregated_contracts_csv
    spending_proactive_grants_csv
  ].freeze

  def fetch
    return fetch_transfer_payment_years if source.format == "spending_transfer_payments_csv"
    return fetch_nserc_years if source.format == "spending_nserc_csv"
    return fetch_sshrc_years if source.format == "spending_sshrc_csv"
    return fetch_global_affairs if source.format == "spending_global_affairs_iati"
    return fetch_cihr if source.format == "spending_cihr_json"
    return fetch_streaming if STREAMING_FORMATS.include?(source.format)

    body = download_body
    process_download(body, checksum: Digest::SHA256.hexdigest(body))
  end

  private

  def fetch_transfer_payment_years
    collector = transfer_payments_collector
    with_retries do
      collector.each_year do |download|
        begin
          process_download(
            download.io,
            checksum: download.checksum,
            filename: "transfer-payments-#{download.year}-#{download.checksum.first(12)}.csv",
            update_last_fetched: false,
            loader_options: { withdrawal_scope: { fiscal_year: download.fiscal_year } }
          )
        ensure
          close_download(download.io)
        end
      end
    end
    source.update!(last_fetched_at: Time.current)
  end

  def fetch_streaming
    download = with_retries do
      Warehouse::Source::Fetcher::StreamingDownload.new(source.url).call
    end
    process_download(download.io, checksum: download.checksum)
  ensure
    close_download(download&.io)
  end

  def fetch_nserc_years
    collector = nserc_collector
    with_retries do
      collector.each_year do |download|
        begin
          process_download(
            download.io,
            checksum: download.checksum,
            filename: "nserc-awards-#{download.year}-#{download.checksum.first(12)}.csv",
            update_last_fetched: false,
            loader_options: { withdrawal_scope: { fiscal_year: download.year } }
          )
        ensure
          close_download(download.io)
        end
      end
    end
    source.update!(last_fetched_at: Time.current)
  end

  def fetch_sshrc_years
    collector = sshrc_collector
    with_retries do
      collector.each_year do |download|
        begin
          process_download(
            download.io,
            checksum: download.checksum,
            filename: "sshrc-awards-#{download.year}-#{download.checksum.first(12)}.csv",
            update_last_fetched: false,
            loader_options: { withdrawal_scope: { fiscal_year: download.year } }
          )
        ensure
          close_download(download.io)
        end
      end
    end
    source.update!(last_fetched_at: Time.current)
  end

  def fetch_global_affairs
    download = with_retries { global_affairs_collector.call }
    process_download(
      download.io,
      checksum: download.checksum,
      filename: "global-affairs-projects-#{download.checksum.first(12)}.csv"
    )
  ensure
    close_download(download&.io)
  end

  def fetch_cihr
    download = with_retries { cihr_collector.call }
    process_download(
      download.io,
      checksum: download.checksum,
      filename: "cihr-awards-#{download.checksum.first(12)}.ndjson"
    )
  ensure
    close_download(download&.io)
  end

  def nserc_collector
    Warehouse::Source::Fetcher::NsercAwards.new(source.url)
  end

  def transfer_payments_collector
    Warehouse::Source::Fetcher::TransferPayments.new(source.url)
  end

  def sshrc_collector
    Warehouse::Source::Fetcher::SshrcAwards.new(source.url)
  end

  def global_affairs_collector
    Warehouse::Source::Fetcher::GlobalAffairsProjects.new(source.url)
  end

  def cihr_collector
    Warehouse::Source::Fetcher::CihrAwards.new(source.url)
  end

  def process_download(body, checksum:, filename: nil, update_last_fetched: true, loader_options: {})
    # A checksum match only skips when the prior load got somewhere: pending
    # and partial may be in flight or awaiting review, and re-dispatching
    # could double-run them. A failed ingestion is retried on the same row
    # (checksum is unique per source), so a load crash can't wedge the source
    # until its upstream data changes.
    existing = source.raw_ingestions.find_by(checksum: checksum)
    if existing && !existing.failed?
      Rails.logger.info "[Fetcher] Source #{source.name}: data unchanged (checksum match), skipping"
      source.update!(last_fetched_at: Time.current) if update_last_fetched
      return
    end

    filename ||= File.basename(URI.parse(source.url).path).presence || "data.#{source.format}"
    r2_key = "raw/#{source.name}/#{Date.current.iso8601}/#{filename}"
    store_raw_file(r2_key, body)
    rewind_body(body)

    ingestion = existing || source.raw_ingestions.new(checksum: checksum)
    ingestion.update!(
      fetched_at: Time.current,
      raw_file_path: r2_key,
      status: :pending,
      error_message: nil
    )

    source.update!(last_fetched_at: Time.current) if update_last_fetched

    dispatch_loader(ingestion, body, **loader_options)

    Rails.logger.info "[Fetcher] Source #{source.name}: ingestion #{ingestion.id} #{existing ? "retried" : "created"}"
  end

  # API-style sources (paginated JSON, multi-step downloads) normalize their
  # payload to a single canonical body at fetch time, so checksum dedupe and
  # the R2 archive operate on exactly what the loader parses.
  def download_body
    case source.format
    when "worldbank_json"
      with_retries { Warehouse::Source::Fetcher::WorldBankDownload.new(source.url).call }
    when "statcan_json"
      with_retries { Warehouse::Source::Fetcher::StatcanVectors.new(source.url).call }
    when "toronto_candidates_json"
      with_retries { Warehouse::Source::Fetcher::TorontoCandidateList.new(source.url, year: election_year).call }
    when "brampton_candidates_html"
      # Brampton and Hamilton have no feed: their candidate pages are scraped
      # and normalized to JSON here.
      with_retries { Warehouse::Source::Fetcher::BramptonCandidateList.new(source.url, year: election_year).call }
    when "hamilton_candidates_html"
      with_retries { Warehouse::Source::Fetcher::HamiltonCandidateList.new(source.url, year: election_year).call }
    else
      download_with_retries
    end
  end

  # Candidate-list sources take their election year from the source name
  # suffix (election_hamilton_2026 → "2026"), which is also how the loaders
  # find the election to load into.
  def election_year
    source.name[/(\d{4})\z/, 1]
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

  def close_download(io)
    return unless io

    io.respond_to?(:close!) ? io.close! : io.close
  end

  def r2_configured?
    Rails.application.credentials.r2.present?
  rescue NoMethodError
    false
  end

  def dispatch_loader(ingestion, body, **loader_options)
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
    when /^election_toronto/
      ingestion.toronto_candidates_loader.load(json_content: body)
    when /^election_brampton/
      ingestion.brampton_candidates_loader.load(json_content: body)
    when /^election_hamilton/
      ingestion.hamilton_candidates_loader.load(json_content: body)
    when /^spending_/
      ingestion.spending_loader.load(body: body, **loader_options)
    else
      Rails.logger.warn "[Fetcher] No loader configured for source: #{source.name}"
    end
  end
end
