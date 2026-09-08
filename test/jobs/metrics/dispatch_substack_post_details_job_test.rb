require "test_helper"

class Metrics::DispatchSubstackPostDetailsJobTest < ActiveJob::TestCase
  class TestJob < Metrics::DispatchSubstackPostDetailsJob
    private

    def settings_for(_publication)
      { cookies: { "substack.sid" => "test" } }.with_indifferent_access
    end
  end

  setup do
    @publication = Metrics::SubstackPublication.create!(
      account_key: "build_canada",
      publication_id: "publication-1",
      url: "https://buildcanada.substack.com"
    )
  end

  test "claims and enqueues a due published post once" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    scheduled_for = now - 1.hour
    post = @publication.posts.create!(
      substack_post_id: "post-1",
      published: true,
      next_details_sync_at: scheduled_for
    )

    assert_enqueued_with(
      job: Metrics::SyncSubstackPostDetailsJob,
      args: [ post, { scheduled_for: scheduled_for } ]
    ) do
      TestJob.perform_now(now: now)
    end

    assert_equal now, post.reload.details_sync_enqueued_at
    assert_no_enqueued_jobs { TestJob.perform_now(now: now) }
  end

  test "does not enqueue drafts" do
    now = Time.zone.parse("2026-08-12 13:00:00")
    @publication.posts.create!(
      substack_post_id: "draft-1",
      published: false,
      next_details_sync_at: now - 1.hour
    )

    assert_no_enqueued_jobs { TestJob.perform_now(now: now) }
  end
end
