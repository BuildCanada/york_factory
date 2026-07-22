require "test_helper"

class LumaEventTest < ActiveSupport::TestCase
  def setup
    @luma_event = LumaEvent.create!(
      luma_event_id: "test-event-123",
      name: "Test Event",
      start_at: 1.day.from_now,
      end_at: 1.day.from_now + 2.hours
    )
  end

  test "should create luma event with required fields" do
    event = LumaEvent.new(
      luma_event_id: "event-456",
      name: "New Event",
      start_at: Time.current
    )
    assert event.save
  end

  test "should require luma_event_id" do
    event = LumaEvent.new(name: "Test", start_at: Time.current)
    assert_not event.save
    assert_includes event.errors.full_messages, "Luma event can't be blank"
  end

  test "should require unique luma_event_id" do
    duplicate = LumaEvent.new(
      luma_event_id: @luma_event.luma_event_id,
      name: "Duplicate",
      start_at: Time.current
    )
    assert_not duplicate.save
    assert_includes duplicate.errors.full_messages, "Luma event has already been taken"
  end

  test "upcoming scope should return future events" do
    past_event = LumaEvent.create!(
      luma_event_id: "past-event",
      name: "Past Event",
      start_at: 1.day.ago
    )

    upcoming_events = LumaEvent.upcoming
    assert_includes upcoming_events, @luma_event
    assert_not_includes upcoming_events, past_event
  end

  test "should calculate duration in hours" do
    assert_equal 2.0, @luma_event.duration_hours
  end

  test "should identify upcoming events" do
    assert @luma_event.upcoming?
    assert_not @luma_event.past?
  end

  test "needs_hubspot_sync scope should return unsynced events" do
    # Event with no hubspot sync
    unsynced_event = LumaEvent.create!(
      luma_event_id: "unsynced-event",
      name: "Unsynced Event",
      start_at: Time.current + 1.day
    )

    # Event that was updated after last sync
    stale_event = LumaEvent.create!(
      luma_event_id: "stale-event",
      name: "Stale Event",
      start_at: Time.current + 1.day,
      hubspot_synced_at: 1.hour.ago
    )
    # Simulate the event being updated after sync
    stale_event.update_column(:updated_at, 30.minutes.ago)

    # Event that's up to date
    synced_event = LumaEvent.create!(
      luma_event_id: "synced-event",
      name: "Synced Event",
      start_at: Time.current + 1.day,
      hubspot_synced_at: 10.minutes.ago
    )
    synced_event.update_column(:updated_at, 20.minutes.ago)

    events_needing_sync = LumaEvent.needs_hubspot_sync

    assert_includes events_needing_sync, unsynced_event
    assert_includes events_needing_sync, stale_event
    assert_not_includes events_needing_sync, synced_event
  end

  test "sync_to_hubspot_if_needed should sync when token present" do
    credentials = Rails.application.credentials
    credentials.define_singleton_method(:dig) do |*keys|
      "test-token" if keys == [ :hubspot, :access_token ]
    end

    sync_enqueued = false
    @luma_event.define_singleton_method(:sync_to_hubspot_later) { sync_enqueued = true }

    @luma_event.sync_to_hubspot_if_needed

    assert sync_enqueued
  ensure
    credentials.singleton_class.remove_method(:dig)
  end

  test "sync_to_hubspot_if_needed should not sync when token missing" do
    credentials = Rails.application.credentials
    credentials.define_singleton_method(:dig) { |*_keys| nil }

    sync_enqueued = false
    @luma_event.define_singleton_method(:sync_to_hubspot_later) { sync_enqueued = true }

    @luma_event.sync_to_hubspot_if_needed

    assert_not sync_enqueued
  ensure
    credentials.singleton_class.remove_method(:dig)
  end
end
