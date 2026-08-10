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
end
