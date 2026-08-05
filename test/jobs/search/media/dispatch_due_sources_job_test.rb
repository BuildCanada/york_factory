require "test_helper"

class Search::Media::DispatchDueSourcesJobTest < ActiveJob::TestCase
  test "claims only due media feeds and advances their schedule before enqueueing" do
    due = Search::Source.create!(
      name: "Due feed",
      realm: "media",
      strategy: "rss",
      url: "https://example.com/feed",
      cadence_seconds: 300,
      next_fetch_at: 1.minute.ago
    )
    future = Search::Source.create!(
      name: "Future feed",
      realm: "media",
      strategy: "rss",
      url: "https://example.com/future",
      cadence_seconds: 300,
      next_fetch_at: 10.minutes.from_now
    )

    assert_enqueued_with(job: Search::Media::FetchSourceJob, args: [ due.id ]) do
      Search::Media::DispatchDueSourcesJob.perform_now(at: Time.current)
    end

    assert due.reload.next_fetch_at.future?
    assert future.reload.next_fetch_at.future?
  end
end
