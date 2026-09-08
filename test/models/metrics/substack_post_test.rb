require "test_helper"

class Metrics::SubstackPostTest < ActiveSupport::TestCase
  setup do
    @published_at = Time.zone.parse("2026-01-01 12:00:00")
    publication = Metrics::SubstackPublication.create!(
      account_key: "build_canada",
      publication_id: "publication-1",
      url: "https://buildcanada.substack.com"
    )
    @post = publication.posts.create!(
      substack_post_id: "post-1",
      published_at: @published_at,
      published: true
    )
  end

  test "syncs daily for the first week and weekly afterward" do
    assert_equal @published_at + 1.day,
      @post.next_detail_checkpoint(after: @published_at + 1.hour)
    assert_equal @published_at + 6.days,
      @post.next_detail_checkpoint(after: @published_at + 5.days)
    assert_equal @published_at + 7.days,
      @post.next_detail_checkpoint(after: @published_at + 6.days + 1.hour)
    assert_equal @published_at + 14.days,
      @post.next_detail_checkpoint(after: @published_at + 7.days + 1.hour)
  end

  test "advances idempotently after a successful detail snapshot" do
    scheduled_for = @published_at
    synced_at = @published_at + 2.hours
    @post.update!(next_details_sync_at: scheduled_for, details_sync_enqueued_at: synced_at)

    @post.mark_details_synced!(scheduled_for: scheduled_for, synced_at: synced_at)

    assert_equal @published_at + 1.day, @post.next_details_sync_at
    assert_equal synced_at, @post.details_synced_at
    assert_nil @post.details_sync_enqueued_at

    @post.mark_details_synced!(scheduled_for: scheduled_for, synced_at: synced_at + 1.hour)
    assert_equal synced_at, @post.reload.details_synced_at
  end
end
