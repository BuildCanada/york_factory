require "test_helper"

class Warehouse::Source::FetcherTest < ActiveSupport::TestCase
  class FakeStrategy
    def initialize(downloads, error: nil)
      @downloads = downloads
      @error = error
    end

    def each_download
      @downloads.each { |download| yield download }
      raise @error if @error
    end
  end

  setup do
    @source = Warehouse::Source.create!(
      name: "test_fetcher_#{SecureRandom.hex(4)}",
      url: "https://example.com/data.csv",
      format: "csv",
      fetch_frequency: "weekly"
    )
    @fetcher = @source.fetcher
    @archived = {}
    @loaded = []
    archived = @archived
    @fetcher.define_singleton_method(:store_raw_file) do |key, body|
      archived[key] = body.respond_to?(:read) ? body.read : body
    end
  end

  test "skips an artifact whose complete ingestion already has its checksum" do
    download = build_download("unchanged")
    ingestion = create_ingestion(download.checksum, status: "complete")

    run_fetch(download)

    assert_empty @archived
    assert_empty @loaded
    assert_equal [ ingestion.id ], @source.raw_ingestions.ids
    assert download.body.closed?
    assert_not_nil @source.reload.last_fetched_at
  end

  test "does not double-run pending or partial ingestions" do
    %w[pending partial].each do |status|
      download = build_download(status)
      ingestion = create_ingestion(download.checksum, status:)

      run_fetch(download)

      assert_empty @loaded, "expected no load for #{status} ingestion"
      assert download.body.closed?
      ingestion.destroy!
    end
  end

  test "retries a failed ingestion on the same row" do
    download = build_download("retry me")
    ingestion = create_ingestion(download.checksum, status: "failed", error_message: "boom")

    run_fetch(download)

    assert_equal [ ingestion.id ], @loaded.map(&:id)
    assert_equal "retry me", @archived.values.sole
    ingestion.reload
    assert_equal "pending", ingestion.status
    assert_nil ingestion.error_message
    assert_equal 1, @source.raw_ingestions.count
  end

  test "archives and loads every artifact with its source-owned filename" do
    first = build_download("first", filename: "first.csv")
    second = build_download("second", filename: "second.csv")

    run_fetch(first, second)

    assert_equal %w[first second], @archived.values
    assert_equal 2, @source.raw_ingestions.count
    assert_equal 2, @loaded.size
    assert @archived.keys.any? { |key| key.end_with?("/first.csv") }
    assert @archived.keys.any? { |key| key.end_with?("/second.csv") }
    assert first.body.closed?
    assert second.body.closed?
    assert_not_nil @source.reload.last_fetched_at
  end

  test "keeps completed artifacts but does not mark the source fetched when a later artifact fails" do
    first = build_download("first", filename: "first.csv")
    strategy = FakeStrategy.new([ first ], error: "second failed")
    install_strategy(strategy)
    @fetcher.define_singleton_method(:with_retries) { |&block| block.call }

    error = assert_raises(RuntimeError) { @fetcher.fetch }

    assert_equal "second failed", error.message
    assert_equal 1, @source.raw_ingestions.count
    assert_nil @source.reload.last_fetched_at
    assert first.body.closed?
  end

  test "registry selects specialized download strategies by source format" do
    expected = {
      "worldbank_json" => Warehouse::Source::Fetcher::WorldBankDownload,
      "statcan_json" => Warehouse::Source::Fetcher::StatcanVectors,
      "toronto_candidates_json" => Warehouse::Source::Fetcher::TorontoCandidateList,
      "brampton_candidates_html" => Warehouse::Source::Fetcher::BramptonCandidateList,
      "hamilton_candidates_html" => Warehouse::Source::Fetcher::HamiltonCandidateList,
      "spending_transfer_payments_csv" => Warehouse::Source::Fetcher::TransferPayments,
      "spending_nserc_csv" => Warehouse::Source::Fetcher::NsercAwards,
      "spending_sshrc_csv" => Warehouse::Source::Fetcher::SshrcAwards,
      "spending_global_affairs_iati" => Warehouse::Source::Fetcher::GlobalAffairsProjects,
      "spending_cihr_json" => Warehouse::Source::Fetcher::CihrAwards,
      "spending_proactive_contracts_csv" => Warehouse::Source::Fetcher::HttpFile
    }

    expected.each do |format, strategy_class|
      source = Warehouse::Source.new(
        name: format.include?("candidates") ? "election_test_2026" : "source",
        url: "https://example.com/data",
        format:
      )

      assert_instance_of strategy_class, Warehouse::Source::Fetcher::Registry.for(source), format
    end
  end

  test "atomically discards concurrent fetches for the same source" do
    job_class = Warehouse::Source::Fetcher::FetchJob
    job = job_class.new(@fetcher)

    assert_equal 1, job_class.concurrency_limit
    assert_equal :discard, job_class.concurrency_on_conflict
    assert_equal 6.hours, job_class.concurrency_duration
    assert_includes job.concurrency_key, "Warehouse::Source/#{@source.id}"
  end

  private

  def run_fetch(*downloads)
    install_strategy(FakeStrategy.new(downloads))
    @fetcher.fetch
  end

  def install_strategy(strategy)
    @fetcher.define_singleton_method(:strategy) { strategy }
  end

  def build_download(body, filename: nil)
    loaded = @loaded
    io = StringIO.new(body)
    Warehouse::Source::Fetcher::Download.new(
      body: io,
      checksum: Digest::SHA256.hexdigest(body),
      filename:
    ) { |ingestion, _content| loaded << ingestion }
  end

  def create_ingestion(checksum, status:, error_message: nil)
    @source.raw_ingestions.create!(
      fetched_at: 1.week.ago,
      raw_file_path: "raw/#{@source.name}/old/data.csv",
      checksum:,
      status:,
      error_message:
    )
  end
end
