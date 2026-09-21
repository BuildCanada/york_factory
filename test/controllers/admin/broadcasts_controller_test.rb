require "test_helper"

class Admin::BroadcastsControllerTest < ActionDispatch::IntegrationTest
  include AdminTestHelper
  include ActiveJob::TestHelper

  setup do
    sign_in_admin
    @now = Time.utc(2026, 9, 21, 14)
    @stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", title_en: "Committee broadcast", first_seen_at: @now, last_seen_at: @now)
    @recording = @stream.recordings.create!(recording_key: "event", starts_at: @now, title_en: "Committee broadcast")
    @audio = @stream.tracks.create!(track_key: "en", kind: "audio", language: "en", role: "main",
      delivery: "separate", first_seen_at: @now, last_seen_at: @now)
  end

  test "lists recordings and renders an empty recording workspace" do
    get admin_broadcasts_path
    assert_response :success
    assert_select "a[href='#{admin_broadcast_path(@recording)}']", "Committee broadcast"
    get admin_broadcast_path(@recording)
    assert_response :success
    assert_select "h1", "Committee broadcast"
    assert_select "form[action='#{admin_media_clips_path(recording_id: @recording.id)}']"
  end

  test "capture toggle invalidates old lease and enqueues enablement" do
    state = MediaCaptureState.create!(media_stream_id: @stream.id)
    assert_enqueued_with(job: Warehouse::Broadcasts::CaptureJob, args: [ @stream.id ]) do
      patch admin_toggle_broadcast_stream_path(@stream)
    end
    assert state.reload.enabled?
    state.update!(lease_token: "old", lease_expires_at: 2.minutes.from_now)
    patch admin_toggle_broadcast_stream_path(@stream)
    assert_not state.reload.enabled?
    assert_nil state.lease_token
  end

  test "rejects audio selections from a different stream" do
    other = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: @now, last_seen_at: @now)
    track = other.tracks.create!(track_key: "en", kind: "audio", language: "en", role: "main",
      delivery: "separate", first_seen_at: @now, last_seen_at: @now)
    get admin_broadcast_path(@recording, audio_track_id: track.id)
    assert_response :not_found
  end

  test "anonymous users cannot list recordings or fetch playlists" do
    delete destroy_user_session_path
    get admin_broadcasts_path
    assert_redirected_to new_user_session_path
    get playlist_admin_broadcast_path(@recording)
    assert_redirected_to new_user_session_path
  end

  test "search ranks published passages from TIN and links to recording offsets" do
    track = @stream.tracks.create!(track_key: "cc-en", kind: "captions", language: "en", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    passage = track.passages.create!(window_key: "1", starts_at: @now + 60, ends_at: @now + 90,
      text: "housing discussion")
    get admin_broadcasts_path(q: "housing")
    assert_response :success
    assert_select "a[href='#{admin_broadcast_path(@recording, at: 60.0, q: "housing", subtitle_language: "en")}']"
    assert_select "p", text: "housing discussion"
    assert_select "mark.broadcast-match", text: "housing"
  end

  test "malformed TinQL shows a useful error" do
    create_caption_passage
    get admin_broadcasts_path(q: "housing OR")

    assert_response :success
    assert_select ".flash-alert", text: /query is not valid/
  end

  test "archive search reports backend failures without calling them malformed input" do
    failure = ActiveRecord::StatementInvalid.new("PG::UndefinedFunction: operator does not exist")
    search = Object.new
    search.define_singleton_method(:ranked) { raise failure }

    Warehouse::Broadcasts::TranscriptSearch.stub(:new, search) do
      get admin_broadcasts_path(q: "housing")
    end

    assert_response :success
    assert_select ".flash-alert", text: /temporarily unavailable/
    assert_select ".flash-alert", text: /not valid/, count: 0
  end
  test "subtitle search covers the entire recording and supplies clip boundaries" do
    track = @stream.tracks.create!(track_key: "cc-fr", kind: "captions", language: "fr", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    track.passages.create!(window_key: "late", starts_at: @now + 3600, ends_at: @now + 3630,
      text: "Le comité discute du logement.")
    get admin_broadcast_path(@recording, q: "logement", subtitle_language: "fr", clip_start: 3500, clip_end: 3650)
    assert_response :success
    assert_select "mark", "logement"
    assert_select "button[data-action='broadcast-player#selectSegment'][data-start='3600.0'][data-end='3630.0']"
    assert_select "input[name='media_clip[start_offset]'][value='3500.0']"
    assert_select "input[name='media_clip[end_offset]'][value='3650.0']"
    get admin_broadcast_path(@recording, q: "logement", subtitle_language: "en")
    assert_select "button[data-action='broadcast-player#selectSegment']", count: 0
  end

  test "subtitle search excludes other recording windows and supports TinQL wildcards" do
    @recording.update!(ends_at: @now + 120)
    track = @stream.tracks.create!(track_key: "cc-en", kind: "captions", language: "en", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    track.passages.create!(window_key: "inside", starts_at: @now + 30, ends_at: @now + 60, text: "Budget is 50% complete")
    track.passages.create!(window_key: "outside", starts_at: @now + 180, ends_at: @now + 210, text: "Outside 50%")
    get admin_broadcast_path(@recording, q: "50*")
    assert_response :success
    assert_select "button[data-action='broadcast-player#selectSegment']", count: 1
    assert_select "input[name='media_clip[end_offset]'][value='30.0']"
  end

  test "malformed TinQL in subtitle search keeps the recording workspace usable" do
    create_caption_passage
    get admin_broadcast_path(@recording, q: "housing OR")

    assert_response :success
    assert_select ".flash-alert", text: /subtitle query is not valid/
    assert_select "form[action='#{admin_media_clips_path(recording_id: @recording.id)}']"
  end
  test "exact subtitle cues are rebased to recording offsets and scoped to the recording" do
    track = @stream.tracks.create!(track_key: "cc-en", kind: "captions", language: "en", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    passage = track.passages.create!(window_key: "cues", starts_at: @now + 60, ends_at: @now + 90, text: "Housing testimony")
    presentation = Object.new
    presentation.define_singleton_method(:call) { "WEBVTT\n\n00:00:02.500 --> 00:00:04.750\nHousing testimony\n" }
    Warehouse::Broadcasts::CaptionPresentation.stub(:new, ->(*args, **kwargs) { presentation }) do
      get subtitle_cues_admin_broadcast_path(@recording, passage_id: passage.id)
    end
    assert_response :success
    assert_equal({ "text" => "Housing testimony", "start" => 62.5, "end" => 64.75 }, response.parsed_body.fetch("cues").sole)
    Warehouse::Broadcasts::CaptionPresentation.stub(:new, ->(*args, **kwargs) { presentation }) do
      get subtitle_cues_admin_broadcast_path(@recording, passage_id: passage.id, q: "housing")
    end
    assert_response :success
    cue = response.parsed_body.fetch("cues").sole
    assert_equal 62.5, cue.fetch("start")
    assert_equal [ { "text" => "Housing", "match" => true }, { "text" => " testimony", "match" => false } ], cue.fetch("segments")
    @recording.update!(ends_at: @now + 30)
    get subtitle_cues_admin_broadcast_path(@recording, passage_id: passage.id)
    assert_response :not_found
    delete destroy_user_session_path
    get subtitle_cues_admin_broadcast_path(@recording, passage_id: passage.id)
    assert_redirected_to new_user_session_path
  end
  test "highlights accented query matches while escaping transcript markup" do
    track = @stream.tracks.create!(track_key: "cc-fr", kind: "captions", language: "fr", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    track.passages.create!(window_key: "escaped", starts_at: @now + 60, ends_at: @now + 90,
      text: "<script>alert(1)</script> Le comité examine le logement & les loyers.")

    get admin_broadcast_path(@recording, q: "comite OR logement", subtitle_language: "fr")

    assert_response :success
    assert_select ".broadcast-transcript mark.broadcast-match", text: "comité"
    assert_select ".broadcast-transcript mark.broadcast-match", text: "logement"
    assert_select ".broadcast-transcript script", count: 0
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_select "form[action='#{admin_media_clips_path(recording_id: @recording.id)}']"
  end
  test "rejects playback offsets beyond a closed recording" do
    @recording.update!(ends_at: @now + 120)
    get admin_broadcast_path(@recording, at: 130)
    assert_redirected_to admin_broadcast_path(@recording)
    get playlist_admin_broadcast_path(@recording, at: 130)
    assert_response :unprocessable_entity
  end

  test "editor exposes selected audio coverage and gaps without superseded footage" do
    [ [ 0, 60, {} ], [ 70, 100, {} ], [ 60, 70, { "superseded_by_id" => 999 } ] ].each_with_index do |(from, to, extra), index|
      @stream.objects.create!(kind: "playback_part", identity_key: "editor-#{index}", object_key: "editor-#{index}",
        checksum: SecureRandom.hex(32), byte_size: 100, content_type: "video/mp2t",
        starts_at: @now + from, ends_at: @now + to, metadata: { "audio_track_id" => @audio.id.to_s }.merge(extra))
    end
    get admin_broadcast_path(@recording, at: 90)
    assert_response :success
    assert_select "[data-broadcast-player-available-end-value='100.0']"
    assert_select "[data-broadcast-player-gaps-value='[[60.0,70.0]]']"
    assert_select "input[name='media_clip[end_offset]'][value='100.0']"
    assert_select "select[name='media_clip[export_mode]'] option[selected][value='exact']"
  end

  test "browsing subtitles presents chronological boundaries" do
    early = create_caption_passage
    early.track.passages.create!(window_key: "earlier", starts_at: @now + 10, ends_at: @now + 20,
      text: "earlier discussion")
    get admin_broadcast_path(@recording)
    offsets = css_select("button[data-action='broadcast-player#selectSegment']").map { |node| node["data-start"].to_f }
    assert_equal [ 10.0, 60.0 ], offsets
  end

  private

  def create_caption_passage
    track = @stream.tracks.create!(track_key: "cc-en-#{SecureRandom.hex(4)}", kind: "captions", language: "en",
      role: "captions", delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    track.passages.create!(window_key: "query-error", starts_at: @now + 60, ends_at: @now + 90,
      text: "housing discussion")
  end
end
