require "test_helper"

class Warehouse::Broadcasts::TranscriptSearchTest < ActiveSupport::TestCase
  setup do
    @now = Time.utc(2026, 9, 21, 14)
    @stream = Warehouse::MediaStream.create!(provider: "cpac", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: @now, last_seen_at: @now)
    @recording = @stream.recordings.create!(recording_key: "event", starts_at: @now, ends_at: @now + 2.hours)
    @english = @stream.tracks.create!(track_key: "cc-en", kind: "captions", language: "en", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    @french = @stream.tracks.create!(track_key: "cc-fr", kind: "captions", language: "fr", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
  end

  test "ranked search uses TinQL with case and accent folding" do
    weaker = passage(@english, "weaker", 10, "The committee discussed energy policy.")
    stronger = passage(@english, "stronger", 20, "Energy policy needs clean energy investment.")
    passage(@english, "unrelated", 30, "A procedural vote followed.")
    passage(@english, "withdrawn", 40, "Energy policy energy", state: "withdrawn")

    results = search(query: "ENERGY policy").ranked.to_a

    assert_equal [ stronger.id, weaker.id ].sort, results.map(&:id).sort
    assert_operator results.first.search_score, :>=, results.last.search_score
  end

  test "accepts documented TinQL syntax and filters language, recording, and dates" do
    matching = passage(@french, "inside", 20, "Le comite parle de logement abordable.")
    passage(@english, "wrong-language", 30, "The committee discusses affordable housing.")
    passage(@french, "outside-recording", 180, "Le comité parle de logement abordable.")

    other_stream = Warehouse::MediaStream.create!(provider: "other", external_id: SecureRandom.uuid,
      kind: "event", first_seen_at: @now, last_seen_at: @now)
    other_track = other_stream.tracks.create!(track_key: "cc-fr", kind: "captions", language: "fr", role: "captions",
      delivery: "embedded", first_seen_at: @now, last_seen_at: @now)
    passage(other_track, "other-provider", 20, "Le comité parle de logement abordable.")

    results = search(query: '"comité parle" AND logement', language: "fr", recording: @recording).chronological

    assert_equal [ matching ], results.to_a
  end

  test "chronological search orders matching subtitle passages by time" do
    later = passage(@english, "later", 50, "Housing affordability")
    earlier = passage(@english, "earlier", 10, "Affordable housing")

    assert_equal [ earlier, later ], search(query: "housing", recording: @recording).chronological.to_a
  end

  test "ranked and chronological searches expose native Tin highlights" do
    passage = passage(@english, "highlighted", 10, "Clean ENERGY powers clean industry.")

    [ search(query: "energy OR industry").ranked.first,
      search(query: "energy OR industry").chronological.first ].each do |result|
      assert_equal passage.id, result.id
      assert_equal [
        { text: "Clean ", match: false },
        { text: "ENERGY", match: true },
        { text: " powers clean ", match: false },
        { text: "industry", match: true },
        { text: ".", match: false }
      ], Warehouse::Broadcasts::TranscriptSearch.segments(text: result.text,
        highlighted_text: result.highlighted_text)
    end
  end

  test "batched cue highlights support phrases accents wildcards OR and exclusions" do
    texts = [
      "Le comité parle de logements.",
      "A housing proposal was excluded.",
      "Affordable homes were discussed."
    ]
    query = '"comite parle" OR afford*'

    segments = Warehouse::Broadcasts::TranscriptSearch.highlight_segments(texts:, query:)

    assert_equal texts, segments.map { |parts| parts.pluck(:text).join }
    assert_equal "comité parle", segments[0].select { _1[:match] }.pluck(:text).join
    assert_empty segments[1].select { _1[:match] }
    assert_equal "Affordable", segments[2].select { _1[:match] }.pluck(:text).join

    excluded = Warehouse::Broadcasts::TranscriptSearch.highlight_segments(
      texts: [ "Housing was discussed without the excluded proposal." ],
      query: "housing AND NOT excluded"
    ).first
    assert_equal "Housing", excluded.select { _1[:match] }.pluck(:text).join
  end

  test "segment decoding safely falls back when source text contains reserved markers" do
    start_marker = Warehouse::Broadcasts::TranscriptSearch::HIGHLIGHT_START
    end_marker = Warehouse::Broadcasts::TranscriptSearch::HIGHLIGHT_END
    text = "before #{start_marker} energy #{end_marker} after"
    highlighted = text.sub("energy", "#{start_marker}energy#{end_marker}")

    segments = Warehouse::Broadcasts::TranscriptSearch.segments(text:, highlighted_text: highlighted)

    assert_equal [ { text:, match: false } ], segments
  end

  test "segments returns plain text for passages loaded outside a search" do
    passage = passage(@english, "plain", 10, "Unsearched subtitle text")

    assert_equal [ { text: passage.text, match: false } ],
      Warehouse::Broadcasts::TranscriptSearch.segments(passage)
  end

  test "batched highlights preserve multiline cue whitespace" do
    text = "The women’s entrepreneur\norganizations of Canada only met"

    segments = Warehouse::Broadcasts::TranscriptSearch.highlight_segments(texts: [ text ], query: "Canada").first

    assert_equal text, segments.pluck(:text).join
    assert_equal "Canada", segments.select { _1[:match] }.pluck(:text).join
  end

  test "batched highlights treat SQL-looking caption contents as text" do
    text = "Housing'); DROP TABLE warehouse.media_tracks; --"
    segments = Warehouse::Broadcasts::TranscriptSearch.highlight_segments(texts: [ text ], query: "housing").first

    assert_equal text, segments.pluck(:text).join
    assert_equal "Housing", segments.select { _1[:match] }.pluck(:text).join
    assert Warehouse::MediaTrack.exists?(@english.id)
  end

  test "stream and date filters constrain archive searches" do
    inside = passage(@english, "inside-day", 10, "housing")
    passage(@english, "outside-day", 70, "housing")

    results = search(query: "housing", stream_id: @stream.id,
      starts_at: @now, ends_at: @now + 1.hour).ranked

    assert_equal [ inside ], results.to_a
  end

  test "committed corrections and withdrawals are visible without an index sync" do
    passage = passage(@english, "corrected", 10, "housing proposal")
    assert_equal [ passage ], search(query: "housing").chronological.to_a

    passage.update!(text: "transit proposal")
    assert_empty search(query: "housing").chronological.to_a
    assert_equal [ passage ], search(query: "transit").chronological.to_a

    passage.update!(state: "withdrawn")
    assert_empty search(query: "transit").chronological.to_a
  end

  test "query values are bound instead of interpolated into SQL" do
    relation = search(query: "housing' OR *").ranked

    assert_includes relation.to_sql, %(.text ==> 'housing'' OR *')
  end

  test "distinguishes TinQL errors from backend failures" do
    malformed = ActiveRecord::StatementInvalid.new("PG::InternalError: invalid ==> query: expected a term")
    unavailable = ActiveRecord::StatementInvalid.new("PG::UndefinedFunction: operator does not exist")

    assert Warehouse::Broadcasts::TranscriptSearch.query_error?(malformed)
    assert_not Warehouse::Broadcasts::TranscriptSearch.query_error?(unavailable)
  end

  private

  def search(**options)
    Warehouse::Broadcasts::TranscriptSearch.new(**options)
  end

  def passage(track, key, offset_minutes, text, state: "published")
    track.passages.create!(window_key: key, starts_at: @now + offset_minutes.minutes,
      ends_at: @now + offset_minutes.minutes + 30.seconds, text: text, state: state)
  end
end
