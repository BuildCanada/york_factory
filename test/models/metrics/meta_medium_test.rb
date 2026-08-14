require "test_helper"

class Metrics::MetaMediumTest < ActiveSupport::TestCase
  setup do
    @published_at = Time.zone.parse("2026-01-01 12:00:00")
    @account = Metrics::MetaAccount.create!(
      platform: "instagram",
      account_key: "build_canada",
      platform_account_id: "ig-account"
    )
    @medium = @account.media.create!(
      platform_media_id: "ig-post",
      published_at: @published_at
    )
  end

  test "builds daily, weekly, and monthly insight checkpoints" do
    checkpoints = @medium.insight_checkpoints

    assert_equal 54, checkpoints.size
    assert_equal @published_at, checkpoints.first
    assert_equal @published_at + 29.days, checkpoints[29]
    assert_equal @published_at + 37.days, checkpoints[30]
    assert_equal @published_at + 142.days, checkpoints[45]
    assert_equal (@published_at + 142.days).advance(months: 1), checkpoints[46]
    assert_equal (@published_at + 142.days).advance(months: 8), checkpoints.last
  end

  test "advances to the first future checkpoint instead of fabricating missed snapshots" do
    scheduled_for = @published_at
    synced_at = @published_at + 10.days + 1.hour
    @medium.update!(next_insights_sync_at: scheduled_for)

    @medium.mark_insights_synced!(scheduled_for: scheduled_for, synced_at: synced_at)

    assert_equal @published_at + 11.days, @medium.next_insights_sync_at
    assert_equal synced_at, @medium.last_insights_synced_at
    assert_nil @medium.insights_sync_completed_at
  end

  test "completes insight syncing after the final checkpoint" do
    scheduled_for = @medium.insight_checkpoints.last
    synced_at = scheduled_for + 1.hour
    @medium.update!(next_insights_sync_at: scheduled_for)

    @medium.mark_insights_synced!(scheduled_for: scheduled_for, synced_at: synced_at)

    assert_nil @medium.next_insights_sync_at
    assert_equal synced_at, @medium.insights_sync_completed_at
  end

  test "ignores a duplicate job for an obsolete checkpoint" do
    current_checkpoint = @published_at + 1.day
    @medium.update!(next_insights_sync_at: current_checkpoint)

    @medium.mark_insights_synced!(
      scheduled_for: @published_at,
      synced_at: @published_at + 2.days
    )

    assert_equal current_checkpoint, @medium.reload.next_insights_sync_at
    assert_nil @medium.last_insights_synced_at
  end
end
