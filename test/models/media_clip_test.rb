require "test_helper"

class MediaClipTest < ActiveSupport::TestCase
  setup do
    now = Time.current.change(usec: 0)
    @stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: now, last_seen_at: now)
    @recording = @stream.media_recordings.create!(recording_key: "event", starts_at: now)
    @track = @stream.media_tracks.create!(track_key: "audio-en", kind: "audio", language: "en",
      role: "main", delivery: "separate", first_seen_at: now, last_seen_at: now)
    @attributes = {
      user: users(:member), media_recording: @recording, media_track: @track,
      starts_at: now + 1.minute, ends_at: now + 2.minutes, title: "Question period"
    }
  end

  test "accepts a selected track from the recording stream and owns attachments" do
    clip = MediaClip.create!(@attributes)

    assert_equal "queued", clip.state
    assert_equal "copy", clip.export_mode
    assert_respond_to clip, :file
    assert_respond_to clip, :captions
    assert_includes MediaClip.visible_to(users(:member)), clip
    refute_includes MediaClip.visible_to(users(:admin)), clip
  end


  test "stores and validates export mode in metadata" do
    clip = MediaClip.new(@attributes)
    clip.export_mode = "exact"

    assert_predicate clip, :valid?
    assert_equal "exact", clip.export_mode
    assert_equal "exact", clip.metadata.fetch("export_mode")

    clip.export_mode = "lossless-ish"
    assert_not clip.valid?
    assert_includes clip.errors[:export_mode], "is not included in the list"
  end

  test "rejects reversed ranges and a track from another stream" do
    other_stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: @recording.starts_at, last_seen_at: @recording.starts_at)
    other_track = other_stream.media_tracks.create!(track_key: "audio", kind: "audio", language: "fr",
      role: "main", delivery: "separate", first_seen_at: @recording.starts_at,
      last_seen_at: @recording.starts_at)
    clip = MediaClip.new(@attributes.merge(media_track: other_track,
      ends_at: @attributes.fetch(:starts_at)))

    assert_not clip.valid?
    assert_includes clip.errors[:media_track], "must belong to the recording's media stream"
    assert_includes clip.errors[:ends_at], "must be after starts at"
  end

  test "limits clips to 30 minutes within the recording and selects only audio" do
    @recording.update!(ends_at: @recording.starts_at + 2.hours, state: "finalized")
    video = @stream.media_tracks.create!(track_key: "video", kind: "video", language: "und",
      role: "main", delivery: "separate", first_seen_at: @recording.starts_at,
      last_seen_at: @recording.starts_at)
    clip = MediaClip.new(@attributes.merge(media_track: video,
      starts_at: @recording.starts_at - 1.second,
      ends_at: @recording.starts_at + 31.minutes,
      title: "x" * 201))

    assert_not clip.valid?
    assert_includes clip.errors[:title], "is too long (maximum is 200 characters)"
    assert_includes clip.errors[:starts_at], "must be within the recording"
    assert_includes clip.errors[:ends_at], "must be no more than 30 minutes after starts at"
    assert_includes clip.errors[:media_track], "must be an audio track"

    clip.starts_at = @recording.starts_at + 100.minutes
    clip.ends_at = @recording.starts_at + 121.minutes
    clip.valid?
    assert_includes clip.errors[:ends_at], "must be within the recording"
  end
end
