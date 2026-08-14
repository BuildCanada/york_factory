require "test_helper"

class Metrics::DispatchMetaMediaInsightsJobTest < ActiveJob::TestCase
  setup do
    @account = Metrics::MetaAccount.create!(
      platform: "instagram",
      account_key: "build_toronto",
      platform_account_id: "ig-account"
    )
  end

  test "enqueues each due post once with its scheduled checkpoint" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    scheduled_for = now - 1.hour
    medium = @account.media.create!(
      platform_media_id: "ig-post",
      published_at: now - 2.days,
      next_insights_sync_at: scheduled_for
    )

    assert_enqueued_with(
      job: Metrics::SyncMetaMediumInsightsJob,
      args: [ medium, { scheduled_for: scheduled_for } ]
    ) do
      Metrics::DispatchMetaMediaInsightsJob.perform_now(now: now)
    end

    assert_equal now, medium.reload.insights_sync_enqueued_at

    assert_no_enqueued_jobs do
      Metrics::DispatchMetaMediaInsightsJob.perform_now(now: now)
    end
  end

  test "does not enqueue completed or future posts" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    @account.media.create!(
      platform_media_id: "future-post",
      next_insights_sync_at: now + 1.hour
    )
    @account.media.create!(
      platform_media_id: "complete-post",
      insights_sync_completed_at: now
    )

    assert_no_enqueued_jobs do
      Metrics::DispatchMetaMediaInsightsJob.perform_now(now: now)
    end
  end
end
