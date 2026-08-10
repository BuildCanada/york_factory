require "test_helper"

class Search::Media::DispatchDueFeedsJobTest < ActiveJob::TestCase
  test "claims only due media feeds and advances their schedule before enqueueing" do
    due = Warehouse::MediaFeed.create!(
      name: "Due feed",
      strategy: "rss",
      url: "https://example.com/feed",
      publisher_name: "Example", publisher_domain: "example.com", language: "en",
      cadence_seconds: 300,
      next_fetch_at: 1.minute.ago
    )
    future = Warehouse::MediaFeed.create!(
      name: "Future feed",
      strategy: "rss",
      url: "https://example.com/future",
      publisher_name: "Example", publisher_domain: "example.com", language: "en",
      cadence_seconds: 300,
      next_fetch_at: 10.minutes.from_now
    )
    disabled = Warehouse::MediaFeed.create!(
      name: "Disabled feed",
      strategy: "rss",
      url: "https://example.com/disabled",
      publisher_name: "Example", publisher_domain: "example.com", language: "en",
      cadence_seconds: 300,
      enabled: false,
      next_fetch_at: 1.minute.ago
    )

    assert_enqueued_with(job: Search::Media::FetchFeedJob, args: [ due.id ]) do
      Search::Media::DispatchDueFeedsJob.perform_now(at: Time.current)
    end

    assert due.reload.next_fetch_at.future?
    assert future.reload.next_fetch_at.future?
    assert disabled.reload.next_fetch_at.past?
  end

  test "spaces feeds from the same publisher without delaying other publishers" do
    travel_to Time.current.change(usec: 0) do
      first = create_due_feed(name: "Publisher feed one", url: "https://news.example.com/one", domain: "example.com")
      second = create_due_feed(name: "Publisher feed two", url: "https://feeds.example.com/two", domain: "example.com")
      other = create_due_feed(name: "Other publisher", url: "https://other.example/feed", domain: "other.example")

      Search::Media::DispatchDueFeedsJob.perform_now(at: Time.current)

      jobs_by_id = enqueued_jobs.index_by { |job| job.fetch(:args).first }
      assert_nil jobs_by_id.fetch(first.id)[:at]
      assert_equal 5.seconds.from_now.to_f, jobs_by_id.fetch(second.id).fetch(:at)
      assert_nil jobs_by_id.fetch(other.id)[:at]
    end
  end

  private

  def create_due_feed(name:, url:, domain:)
    Warehouse::MediaFeed.create!(
      name: name,
      strategy: "rss",
      url: url,
      publisher_name: name,
      publisher_domain: domain,
      language: "en",
      cadence_seconds: 300,
      next_fetch_at: 1.minute.ago
    )
  end
end
