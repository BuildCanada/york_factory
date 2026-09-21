require "test_helper"

class Admin::MediaClipsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper
  include ActiveJob::TestHelper

  setup do
    sign_in_admin
    @now = Time.utc(2026, 9, 21, 14)
    stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", title_en: "Parliament", first_seen_at: @now, last_seen_at: @now)
    @recording = stream.recordings.create!(recording_key: "event", starts_at: @now, title_en: "Parliament")
  end

  test "saves a clip for the authenticated owner and enqueues export" do
    assert_difference("MediaClip.count", 1) do
      assert_enqueued_jobs 1 do
        post admin_media_clips_path(recording_id: @recording.id), params: {
          media_clip: { title: "Housing", start_offset: "10.5", end_offset: "30" }
        }
      end
    end
    clip = MediaClip.order(:id).last
    assert_equal users(:admin), clip.user
    assert_equal @now + 10.5, clip.starts_at
    assert_equal @now + 30, clip.ends_at
    assert_equal "exact", clip.export_mode
    assert_redirected_to admin_media_clip_path(clip)
    get admin_media_clip_path(clip)
    assert_response :success
    assert_select "p", text: /Export mode: Precise/
  end

  test "accepts fast copy mode and rejects an unknown mode" do
    post admin_media_clips_path(recording_id: @recording.id), params: {
      media_clip: { title: "Fast", start_offset: "10", end_offset: "30", export_mode: "copy" }
    }
    assert_equal "copy", MediaClip.order(:id).last.export_mode

    assert_no_difference("MediaClip.count") do
      post admin_media_clips_path(recording_id: @recording.id), params: {
        media_clip: { title: "Unknown", start_offset: "10", end_offset: "30", export_mode: "turbo" }
      }
    end
    assert_redirected_to admin_broadcast_path(@recording)
  end

  test "rejects invalid or unbounded intervals" do
    assert_no_difference("MediaClip.count") do
      post admin_media_clips_path(recording_id: @recording.id), params: {
        media_clip: { title: "Too long", start_offset: "0", end_offset: "1801" }
      }
    end
    assert_redirected_to admin_broadcast_path(@recording)
  end

  test "even another admin cannot access a private clip" do
    other = User.where.not(id: users(:admin).id).first!
    clip = MediaClip.create!(user: other, media_recording: @recording, title: "Private selection",
      starts_at: @now, ends_at: @now + 30, state: "queued")
    get admin_media_clip_path(clip)
    assert_response :not_found
    get download_admin_media_clip_path(clip)
    assert_response :not_found
  end
end
