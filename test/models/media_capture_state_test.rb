require "test_helper"

class MediaCaptureStateTest < ActiveSupport::TestCase
  setup do
    now = Time.current
    stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "continuous", first_seen_at: now, last_seen_at: now)
    @state = MediaCaptureState.create!(media_stream: stream, enabled: true)
    @now = now.change(usec: 0)
  end

  test "claims, renews, updates, and releases with fencing" do
    token = @state.claim!(now: @now, ttl: 30.seconds)
    assert token.present?
    assert_nil @state.claim!(now: @now + 1.second, ttl: 30.seconds)
    assert @state.lease_owned?(token, now: @now + 1.second)
    assert @state.renew_lease!(token:, now: @now + 2.seconds, ttl: 1.minute)
    assert @state.update_cursor!(token:, now: @now + 3.seconds,
      cursor: { "video" => 42 }, attrs: { last_captured_at: @now + 3.seconds })
    assert_equal 42, @state.reload.cursor.fetch("video")
    assert @state.release_lease!(token:, now: @now + 4.seconds,
      attrs: { next_poll_at: @now + 10.seconds })
    assert_nil @state.reload.lease_token
  end

  test "expired or mismatched owners cannot mutate fenced state" do
    token = @state.claim!(now: @now, ttl: 1.second)

    refute @state.renew_lease!(token: "other", now: @now, ttl: 30.seconds)
    refute @state.update_cursor!(token:, now: @now + 2.seconds, cursor: { "video" => 9 })
    assert_equal({}, @state.reload.cursor)
  end

  test "disabled states cannot be claimed" do
    @state.update!(enabled: false)

    assert_nil @state.claim!(now: @now, ttl: 30.seconds)
  end

  test "duplicate queued polls cannot bypass the next due time" do
    token = @state.claim!(now: @now, ttl: 30.seconds)
    @state.release_lease!(token: token, now: @now, attrs: { next_poll_at: @now + 6.seconds })
    assert_nil @state.claim!(now: @now + 1.second, ttl: 30.seconds)
    assert @state.claim!(now: @now + 6.seconds, ttl: 30.seconds)
  end
end
