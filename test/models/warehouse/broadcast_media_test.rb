require "test_helper"

class Warehouse::BroadcastMediaTest < ActiveJob::TestCase
  setup do
    @now = Time.current.change(usec: 0)
    @stream = Warehouse::MediaStream.create!(
      provider: "cpac",
      external_id: "event-#{SecureRandom.hex(4)}",
      kind: "event",
      title_en: "Committee meeting",
      title_fr: "Réunion du comité",
      page_url_en: "https://www.cpac.ca/event/en",
      page_url_fr: "https://www.cpac.ca/event/fr",
      manifest_url: "https://cdn.example.test/live.m3u8",
      first_seen_at: @now,
      last_seen_at: @now
    )
    @track = @stream.media_tracks.create!(
      track_key: "captions-en",
      kind: "captions",
      language: "en",
      role: "captions",
      delivery: "embedded",
      first_seen_at: @now,
      last_seen_at: @now
    )
  end

  test "stream identity and track parent ownership are validated" do
    duplicate = @stream.dup
    assert_not duplicate.valid?
    assert duplicate.errors.added?(:external_id, :taken, value: @stream.external_id)

    other_stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: @now, last_seen_at: @now)
    parent = other_stream.media_tracks.create!(track_key: "video", kind: "video", language: "und",
      role: "main", delivery: "separate", first_seen_at: @now, last_seen_at: @now)
    @track.parent_track = parent

    assert_not @track.valid?
    assert_includes @track.errors[:parent_track], "must belong to the same media stream"
  end

  test "media objects are idempotently identified, overlap strictly, and keep uploaded bytes immutable" do
    object = @stream.media_objects.create!(media_track: @track, kind: "source_segment",
      identity_key: "segment:0:12", object_key: "cpac/test/#{SecureRandom.uuid}.ts",
      checksum: "sha256:test", byte_size: 128, content_type: "video/mp2t",
      starts_at: @now, ends_at: @now + 6.seconds, epoch: 0, sequence: 12)

    assert_equal [ object ], Warehouse::MediaObject.overlapping(@now + 1.second, @now + 2.seconds).to_a
    assert_empty Warehouse::MediaObject.overlapping(@now + 6.seconds, @now + 8.seconds)

    object.checksum = "sha256:changed"
    assert_not object.valid?
    assert_includes object.errors[:base], "uploaded media object attributes are immutable"
  end

  test "recordings with nullable ends overlap windows and reject reversed ranges" do
    recording = @stream.media_recordings.create!(recording_key: "2026-09-21", starts_at: @now)

    assert_includes @stream.media_recordings.overlapping(@now + 1.hour, @now + 2.hours), recording
    recording.ends_at = @now - 1.second
    assert_not recording.valid?
  end

  test "transcript passage changes stay in Postgres without search sync jobs" do
    passage = nil
    assert_no_enqueued_jobs only: Search::SyncJob do
      passage = @track.media_transcript_passages.create!(window_key: "window-1",
        starts_at: @now, ends_at: @now + 30.seconds, text: "Welcome to the committee meeting")
      passage.update!(text: "Corrected committee transcript")
      passage.update!(state: "withdrawn")
    end

    assert_equal "media_transcript_passage:#{passage.id}", passage.search_id
    refute passage.respond_to?(:sync_to_search!)
    assert_nil Searchable.resolve(passage.search_id)
    assert_equal 0, passage.search_revision
    assert_nil passage.search_content_hash
    assert_nil passage.search_synced_at
  end
end
