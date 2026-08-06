require "test_helper"

class Warehouse::Source::FetcherTest < ActiveSupport::TestCase
  BODY = %([{"vectorId":65201210,"refPer":"2025-01-01","value":100.0}]).freeze
  CHECKSUM = Digest::SHA256.hexdigest(BODY)

  setup do
    @source = Warehouse::Source.create!(
      name: "econ_statcan_test_fetcher",
      url: "https://example.com/wds/getData?vectors=65201210",
      format: "statcan_json",
      fetch_frequency: "weekly"
    )
    @fetcher = @source.fetcher
    @dispatched = []
  end

  test "skips when a complete ingestion already has the checksum" do
    ingestion = create_ingestion(status: "complete")

    run_fetch

    assert_empty @dispatched
    assert_equal [ ingestion.id ], @source.raw_ingestions.ids
    assert_not_nil @source.reload.last_fetched_at
  end

  test "skips pending and partial ingestions so in-flight or in-review loads are not double-run" do
    %w[pending partial].each do |status|
      ingestion = create_ingestion(status: status)

      run_fetch

      assert_empty @dispatched, "expected no dispatch for #{status} ingestion"
      ingestion.destroy!
    end
  end

  test "retries a failed ingestion on the same row instead of skipping" do
    ingestion = create_ingestion(status: "failed", error_message: "boom")

    run_fetch

    assert_equal [ ingestion.id ], @dispatched.map(&:id)
    ingestion.reload
    assert_equal "pending", ingestion.status
    assert_nil ingestion.error_message
    assert_equal 1, @source.raw_ingestions.count
    assert_not_nil @source.reload.last_fetched_at
  end

  test "creates a new ingestion and dispatches the loader for unseen data" do
    run_fetch

    assert_equal 1, @dispatched.size
    ingestion = @source.raw_ingestions.sole
    assert_equal CHECKSUM, ingestion.checksum
    assert_equal "pending", ingestion.status
    assert_not_nil @source.reload.last_fetched_at
  end

  test "archives and dispatches each transfer-payment year independently" do
    source = Warehouse::Source.create!(
      name: "spending_transfer_payments",
      url: "https://example.com/transfer-payments-catalogue.json",
      format: "spending_transfer_payments_csv",
      fetch_frequency: "annual"
    )
    fetcher = source.fetcher
    archived = {}
    dispatched = []
    downloads = [
      transfer_payment_download(2003, "2002/2003 payments"),
      transfer_payment_download(2025, "2024/2025 payments")
    ]
    collector = collector_for(*downloads)
    fetcher.define_singleton_method(:store_raw_file) { |key, stream| archived[key] = stream.read }
    fetcher.define_singleton_method(:dispatch_loader) do |ingestion, stream, **options|
      dispatched << [ ingestion, stream.read, options ]
    end
    fetcher.define_singleton_method(:transfer_payments_collector) { collector }

    fetcher.fetch

    assert_equal [ "2002/2003 payments", "2024/2025 payments" ], archived.values
    assert_equal [ 2002, 2024 ], dispatched.map { |_ingestion, _body, options|
      options.dig(:withdrawal_scope, :fiscal_year)
    }
    assert archived.keys.any? { |key| key.match?(/transfer-payments-2003-[a-f0-9]{12}\.csv\z/) }
    assert downloads.all? { |download| download.io.closed? }
    assert_not_nil source.reload.last_fetched_at
  end

  test "keeps completed transfer-payment years when a later year fails" do
    source = Warehouse::Source.create!(
      name: "spending_transfer_payments",
      url: "https://example.com/transfer-payments-catalogue.json",
      format: "spending_transfer_payments_csv"
    )
    fetcher = source.fetcher
    collector = Object.new
    completed_download = transfer_payment_download(2003, "2002/2003 payments")
    collector.define_singleton_method(:each_year) do |&block|
      block.call(completed_download)
      raise "2025 failed"
    end
    fetcher.define_singleton_method(:store_raw_file) { |_key, stream| stream.read }
    fetcher.define_singleton_method(:dispatch_loader) { |_ingestion, stream, **_options| stream.read }
    fetcher.define_singleton_method(:with_retries) { |&block| block.call }
    fetcher.define_singleton_method(:transfer_payments_collector) { collector }

    error = assert_raises(RuntimeError) { fetcher.fetch }

    assert_equal "2025 failed", error.message
    assert_equal 1, source.raw_ingestions.count
    assert_nil source.reload.last_fetched_at
  end

  test "archives and dispatches each NSERC year independently" do
    source = Warehouse::Source.create!(
      name: "spending_nserc_awards",
      url: "https://example.com/nserc-catalogue.json",
      format: "spending_nserc_csv",
      fetch_frequency: "monthly"
    )
    fetcher = source.fetcher
    archived = {}
    dispatched = []
    collector = collector_for(
      nserc_download(1991, "1991 awards"),
      nserc_download(2024, "2024 awards")
    )
    fetcher.define_singleton_method(:store_raw_file) do |key, stream|
      archived[key] = stream.read
    end
    fetcher.define_singleton_method(:dispatch_loader) do |ingestion, stream, **options|
      dispatched << [ ingestion, stream.read, options ]
    end
    fetcher.define_singleton_method(:nserc_collector) { collector }

    fetcher.fetch

    assert_equal 2, source.raw_ingestions.count
    assert_equal [ "1991 awards", "2024 awards" ], archived.values
    assert_equal [ 1991, 2024 ], dispatched.map { |_ingestion, _body, options|
      options.dig(:withdrawal_scope, :fiscal_year)
    }
    assert dispatched.all? { |ingestion, _body, _options| ingestion.complete? || ingestion.pending? }
    assert archived.keys.any? { |key| key.match?(/nserc-awards-1991-[a-f0-9]{12}\.csv\z/) }
    assert_not_nil source.reload.last_fetched_at
  end

  test "keeps completed NSERC years when a later year fails" do
    source = Warehouse::Source.create!(
      name: "spending_nserc_awards",
      url: "https://example.com/nserc-catalogue.json",
      format: "spending_nserc_csv"
    )
    fetcher = source.fetcher
    collector = Object.new
    completed_download = nserc_download(1991, "1991 awards")
    collector.define_singleton_method(:each_year) do |&block|
      block.call(completed_download)
      raise "2024 failed"
    end
    fetcher.define_singleton_method(:store_raw_file) { |_key, stream| stream.read }
    fetcher.define_singleton_method(:dispatch_loader) { |_ingestion, stream, **_options| stream.read }
    fetcher.define_singleton_method(:with_retries) { |&block| block.call }
    fetcher.define_singleton_method(:nserc_collector) { collector }

    error = assert_raises(RuntimeError) { fetcher.fetch }

    assert_equal "2024 failed", error.message
    assert_equal 1, source.raw_ingestions.count
    assert_nil source.reload.last_fetched_at
  end

  test "archives and dispatches each SSHRC year independently" do
    source = Warehouse::Source.create!(
      name: "spending_sshrc_awards",
      url: "https://example.com/sshrc-catalogue.json",
      format: "spending_sshrc_csv",
      fetch_frequency: "monthly"
    )
    fetcher = source.fetcher
    archived = {}
    dispatched = []
    collector = collector_for(
      year_download(1998, "1998 payments"),
      year_download(2024, "2024 payments")
    )
    fetcher.define_singleton_method(:store_raw_file) do |key, stream|
      archived[key] = stream.read
    end
    fetcher.define_singleton_method(:dispatch_loader) do |ingestion, stream, **options|
      dispatched << [ ingestion, stream.read, options ]
    end
    fetcher.define_singleton_method(:sshrc_collector) { collector }

    fetcher.fetch

    assert_equal 2, source.raw_ingestions.count
    assert_equal [ "1998 payments", "2024 payments" ], archived.values
    assert_equal [ 1998, 2024 ], dispatched.map { |_ingestion, _body, options|
      options.dig(:withdrawal_scope, :fiscal_year)
    }
    assert archived.keys.any? { |key| key.match?(/sshrc-awards-1998-[a-f0-9]{12}\.csv\z/) }
    assert_not_nil source.reload.last_fetched_at
  end

  test "keeps completed SSHRC years when a later year fails" do
    source = Warehouse::Source.create!(
      name: "spending_sshrc_awards",
      url: "https://example.com/sshrc-catalogue.json",
      format: "spending_sshrc_csv"
    )
    fetcher = source.fetcher
    collector = Object.new
    completed_download = year_download(1998, "1998 payments")
    collector.define_singleton_method(:each_year) do |&block|
      block.call(completed_download)
      raise "2024 failed"
    end
    fetcher.define_singleton_method(:store_raw_file) { |_key, stream| stream.read }
    fetcher.define_singleton_method(:dispatch_loader) { |_ingestion, stream, **_options| stream.read }
    fetcher.define_singleton_method(:with_retries) { |&block| block.call }
    fetcher.define_singleton_method(:sshrc_collector) { collector }

    error = assert_raises(RuntimeError) { fetcher.fetch }

    assert_equal "2024 failed", error.message
    assert_equal 1, source.raw_ingestions.count
    assert_nil source.reload.last_fetched_at
  end

  test "archives and dispatches the canonical Global Affairs IATI download" do
    source = Warehouse::Source.create!(
      name: "spending_global_affairs_projects",
      url: "https://example.com/global-affairs-iati",
      format: "spending_global_affairs_iati",
      fetch_frequency: "daily"
    )
    fetcher = source.fetcher
    body = "canonical projects"
    download = Struct.new(:io, :checksum).new(StringIO.new(body), Digest::SHA256.hexdigest(body))
    archived_body = nil
    dispatched_body = nil
    collector = Object.new
    collector.define_singleton_method(:call) { download }
    fetcher.define_singleton_method(:global_affairs_collector) { collector }
    fetcher.define_singleton_method(:store_raw_file) { |_key, stream| archived_body = stream.read }
    fetcher.define_singleton_method(:dispatch_loader) { |_ingestion, stream| dispatched_body = stream.read }

    fetcher.fetch

    assert_equal body, archived_body
    assert_equal body, dispatched_body
    assert_equal download.checksum, source.raw_ingestions.sole.checksum
    assert download.io.closed?
    assert_not_nil source.reload.last_fetched_at
  end

  test "archives and dispatches the canonical CIHR NDJSON download" do
    source = Warehouse::Source.create!(
      name: "spending_cihr_awards",
      url: "https://example.com/cihr",
      format: "spending_cihr_json",
      fetch_frequency: "monthly"
    )
    fetcher = source.fetcher
    body = "{\"id\":\"1\"}\n"
    download = Warehouse::Source::Fetcher::CihrAwards::Download.new(
      io: StringIO.new(body), checksum: Digest::SHA256.hexdigest(body)
    )
    archived_body = nil
    dispatched_body = nil
    collector = Object.new
    collector.define_singleton_method(:call) { download }
    fetcher.define_singleton_method(:cihr_collector) { collector }
    fetcher.define_singleton_method(:store_raw_file) { |_key, stream| archived_body = stream.read }
    fetcher.define_singleton_method(:dispatch_loader) { |_ingestion, stream| dispatched_body = stream.read }

    fetcher.fetch

    assert_equal body, archived_body
    assert_equal body, dispatched_body
    assert_equal download.checksum, source.raw_ingestions.sole.checksum
    assert download.io.closed?
  end

  private

  def create_ingestion(status:, error_message: nil)
    @source.raw_ingestions.create!(
      fetched_at: 1.week.ago,
      raw_file_path: "raw/#{@source.name}/old/data.json",
      checksum: CHECKSUM,
      status: status,
      error_message: error_message
    )
  end

  # Stubs the network download and the loader dispatch; everything between
  # (dedupe, archival, ingestion row lifecycle) runs for real.
  def run_fetch
    dispatched = @dispatched
    @fetcher.define_singleton_method(:download_body) { BODY }
    @fetcher.define_singleton_method(:dispatch_loader) { |ingestion, _body| dispatched << ingestion }
    @fetcher.fetch
  end

  def collector_for(*downloads)
    Object.new.tap do |collector|
      collector.define_singleton_method(:each_year) do |&block|
        downloads.each { |download| block.call(download) }
      end
    end
  end

  def nserc_download(year, body)
    checksum = Digest::SHA256.hexdigest(body)
    Warehouse::Source::Fetcher::NsercAwards::YearDownload.new(
      year:,
      url: "https://example.com/#{year}.csv",
      io: StringIO.new(body),
      checksum:
    )
  end

  def transfer_payment_download(year, body)
    checksum = Digest::SHA256.hexdigest(body)
    Warehouse::Source::Fetcher::TransferPayments::YearDownload.new(
      year:,
      fiscal_year: year - 1,
      url: "https://example.com/#{year}.csv",
      io: StringIO.new(body),
      checksum:
    )
  end

  def year_download(year, body)
    Struct.new(:year, :url, :io, :checksum).new(
      year,
      "https://example.com/#{year}.csv",
      StringIO.new(body),
      Digest::SHA256.hexdigest(body)
    )
  end
end
