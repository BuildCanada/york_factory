require "test_helper"

class Admin::BroadcastBackfillsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper
  include ActiveJob::TestHelper

  setup do
    sign_in_admin
  end

  test "queues a discover only date range and displays request progress" do
    assert_difference "BroadcastBackfillRequest.count", 1 do
      post admin_broadcast_backfills_path, params: { starts_on: "2026-09-01", ends_on: "2026-09-02", mode: "discover_only" }
    end
    request = BroadcastBackfillRequest.order(:id).last
    assert_equal "discover_only", request.mode
    assert_redirected_to admin_broadcast_backfill_path(request)
    follow_redirect!
    assert_response :success
    assert_select "h1", "Backfill request ##{request.id}"
  end

  test "queues capture of date range and rejects invalid dates" do
    post admin_broadcast_backfills_path, params: { starts_on: "2026-09-01", ends_on: "2026-09-02", mode: "discover_and_queue" }
    assert_equal "discover_and_queue", BroadcastBackfillRequest.order(:id).last.mode
    assert_no_difference "BroadcastBackfillRequest.count" do
      post admin_broadcast_backfills_path, params: { starts_on: "invalid", ends_on: "2026-09-02", mode: "discover_only" }
    end
    assert_redirected_to admin_broadcast_backfills_path
    assert_no_difference "BroadcastBackfillRequest.count" do
      post admin_broadcast_backfills_path, params: { starts_on: "2026-09-03", ends_on: "2026-09-02", mode: "discover_only" }
    end
  end

  test "lists historical entries and queues one stream" do
    stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid, kind: "on_demand",
      title_en: "Historical housing committee", title_fr: "Comité du logement", manifest_url: "https://cpac.ca/archive.m3u8",
      first_seen_at: Time.current, last_seen_at: Time.current, scheduled_start_at: Time.utc(2026, 9, 1))
    get admin_broadcast_backfills_path(q: "logement")
    assert_response :success
    assert_select "strong", "Historical housing committee"
    assert_difference "BroadcastBackfillRequest.count", 1 do
      post queue_stream_admin_broadcast_backfills_path, params: { media_stream_id: stream.id }
    end
    request = BroadcastBackfillRequest.order(:id).last
    assert_redirected_to admin_broadcast_backfill_path(request)
    assert_equal stream.id, request.items.sole.media_stream_id
  end

  test "anonymous visitors cannot queue or browse backfills" do
    delete destroy_user_session_path
    assert_no_difference "BroadcastBackfillRequest.count" do
      post admin_broadcast_backfills_path, params: { starts_on: "2026-09-01", ends_on: "2026-09-02", mode: "discover_and_queue" }
    end
    assert_redirected_to new_user_session_path
    get admin_broadcast_backfills_path
    assert_redirected_to new_user_session_path
  end
  test "does not expose other providers or live streams as CPAC archive captures" do
    now = Time.current
    other = Warehouse::MediaStream.create!(provider: "other", external_id: SecureRandom.uuid, kind: "on_demand",
      title_en: "Other provider archive", first_seen_at: now, last_seen_at: now)
    get admin_broadcast_backfills_path
    assert_select "strong", text: "Other provider archive", count: 0
    assert_no_difference "BroadcastBackfillRequest.count" do
      post queue_stream_admin_broadcast_backfills_path, params: { media_stream_id: other.id }
    end
    assert_response :not_found
    other.update!(provider: "cpac", kind: "event")
    post queue_stream_admin_broadcast_backfills_path, params: { media_stream_id: other.id }
    assert_response :not_found
  end
end
