require "test_helper"

class TestBroadcastBackfillJob < Warehouse::Broadcasts::BackfillJob
  cattr_accessor :pages

  private

  def adapter
    Struct.new(:pages) do
      def list(start_date:, end_date:, page:)
        pages.fetch([ start_date, end_date, page ])
      end
    end.new(self.class.pages)
  end
end

class Warehouse::Broadcasts::BackfillJobTest < ActiveJob::TestCase
  test "discovers each date durably without queueing capture in discover-only mode" do
    start_date = Date.new(2026, 9, 1)
    entry = Warehouse::Broadcasts::CpacAdapter::Stream.new(
      external_id: "#{SecureRandom.uuid}:archive", kind: "on_demand", title_en: "Archive", title_fr: nil,
      description_en: nil, description_fr: nil, page_url_en: nil, page_url_fr: nil,
      manifest_url: "https://cpac.ca/archive.m3u8", provider_state: "archive",
      scheduled_start_at: start_date.to_time, metadata: { "canonical_external_id" => SecureRandom.uuid }
    )
    empty_page = ->(entries) {
      Warehouse::Broadcasts::CpacHistoryAdapter::Page.new(entries:, errors: [], page: 1,
        total: entries.size, next_page: nil, listing_url: "https://www.cpac.ca/search")
    }
    TestBroadcastBackfillJob.pages = {
      [ start_date, start_date, 1 ] => empty_page.call([ entry ]),
      [ start_date + 1, start_date + 1, 1 ] => empty_page.call([])
    }
    token = SecureRandom.uuid
    request = BroadcastBackfillRequest.create!(scope: "date_range", mode: "discover_only",
      starts_on: start_date, ends_on: start_date + 1, requested_by: users(:admin),
      lease_token: token, lease_expires_at: 5.minutes.from_now)

    assert_no_enqueued_jobs(only: Warehouse::Broadcasts::HistoricalCaptureJob) do
      TestBroadcastBackfillJob.perform_now(request.id, token)
    end

    assert_equal "completed", request.reload.state
    assert_equal 2, request.processed_dates
    assert_equal "skipped", request.items.sole.state
    assert_equal "on_demand", request.items.sole.media_stream.kind
  end


  test "interrupts a large dispatch and resumes remaining items before completion" do
    token = SecureRandom.uuid
    request = BroadcastBackfillRequest.create!(scope: "stream", mode: "discover_only",
      requested_by: users(:admin), lease_token: token, lease_expires_at: 5.minutes.from_now)
    now = Time.current
    101.times do
      stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: "#{SecureRandom.uuid}:archive",
        kind: "on_demand", first_seen_at: now, last_seen_at: now)
      request.items.create!(media_stream: stream)
    end

    TestBroadcastBackfillJob.perform_now(request.id, token)

    assert_not request.reload.orchestration_complete?
    assert_equal 1, request.items.where(state: "discovered").count
    perform_enqueued_jobs(only: TestBroadcastBackfillJob)
    assert request.reload.orchestration_complete?
    assert_equal "completed", request.state
    assert_equal 101, request.items.where(state: "skipped").count
  end

  test "persists listing errors once and retries listing discovery" do
    date = Date.new(2026, 9, 1)
    error = { "url" => "https://www.cpac.ca/episode?id=bad", "external_id" => "bad", "error" => "missing video" }
    page = Warehouse::Broadcasts::CpacHistoryAdapter::Page.new(entries: [], errors: [ error ], page: 1,
      total: 1, next_page: nil, listing_url: "https://www.cpac.ca/search")
    TestBroadcastBackfillJob.pages = { [ date, date, 1 ] => page }
    token = SecureRandom.uuid
    request = BroadcastBackfillRequest.create!(scope: "date_range", mode: "discover_only",
      starts_on: date, ends_on: date, requested_by: users(:admin),
      lease_token: token, lease_expires_at: 5.minutes.from_now)

    TestBroadcastBackfillJob.perform_now(request.id, token)
    request.reload
    assert_equal "failed", request.state
    assert_equal [ error ], request.metadata.fetch("listing_errors")

    assert_enqueued_with(job: Warehouse::Broadcasts::BackfillJob) { request.retry! }
    assert_equal 0, request.reload.processed_dates
    assert_not request.metadata.key?("listing_errors")
  end
end
