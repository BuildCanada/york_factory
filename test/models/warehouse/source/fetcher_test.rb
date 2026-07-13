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
    assert_nil @source.reload.last_fetched_at
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
end
