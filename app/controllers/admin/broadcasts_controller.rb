module Admin
  class BroadcastsController < BaseController
    before_action :set_recording, only: %i[show playlist captions subtitle_cues]

    def index
      @streams = Warehouse::MediaStream.where.not(kind: "on_demand").order(last_seen_at: :desc).limit(100)
      @selected_stream = Warehouse::MediaStream.find_by(id: params[:stream_id]) if params[:stream_id].present?
      @capture_states = MediaCaptureState.where(media_stream_id: @streams.map(&:id)).index_by(&:media_stream_id)
      scope = Warehouse::MediaRecording.includes(:stream).order(starts_at: :desc)
      scope = scope.where(media_stream_id: params[:stream_id]) if params[:stream_id].present?
      if params[:date].present?
        @filter_date = Date.iso8601(params[:date])
        scope = scope.where(starts_at: @filter_date.beginning_of_day...@filter_date.next_day.beginning_of_day)
      end
      @pagy, @recordings = pagy(:offset, scope, limit: 30)
      @clips = MediaClip.where(user: current_user).order(created_at: :desc).limit(10)
      search_passages if params[:q].present?
    rescue Date::Error
      redirect_to admin_broadcasts_path, alert: "Enter a valid date."
    end

    def show
      @at = parse_offset(params[:at])
      @audio_tracks = @recording.stream.tracks.where(kind: "audio").order(:language, last_seen_at: :desc, id: :desc)
      @audio_track = if params[:audio_track_id].present?
        @audio_tracks.find(params[:audio_track_id])
      else
        default_audio(@audio_tracks, at: @at)
      end
      @caption_tracks = @recording.stream.tracks.where(kind: "captions").order(:language, :id)
      @caption_latest = @caption_tracks.index_with { |track| track.objects.where(kind: "caption_file").order(ends_at: :desc).first }
      @playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: @audio_track, at: @at)
      @subtitle_query = params[:q].to_s.strip.first(500)
      scope = Warehouse::MediaTranscriptPassage.where(media_track_id: @caption_tracks.select(:id), state: "published")
        .where("ends_at > ?", @recording.starts_at)
      scope = scope.where("starts_at < ?", @recording.ends_at) if @recording.ends_at
      if @subtitle_query.present?
        scope = Warehouse::Broadcasts::TranscriptSearch.new(query: @subtitle_query,
          language: params[:subtitle_language], recording: @recording).chronological
      else
        scope = scope.where("starts_at < ? AND ends_at > ?", @at + 30.minutes, @at).order(:starts_at, :media_track_id, :id)
        if params[:subtitle_language].in?(%w[en fr])
          scope = scope.where(media_track_id: @caption_tracks.where(language: params[:subtitle_language]).select(:id))
        end
      end
      load_transcript_passages(scope)
      prepare_editor_timeline
      @clip_start = clip_offset(params[:clip_start], fallback: @at - @recording.starts_at)
      @clip_end = clip_offset(params[:clip_end], fallback: [ @clip_start + 30, @available_end.positive? ? @available_end : @clip_start + 30 ].min)
      @capture_state = MediaCaptureState.find_by(media_stream_id: @recording.media_stream_id)
      @clips = MediaClip.where(user: current_user, media_recording_id: @recording.id).order(created_at: :desc).limit(20)
    rescue ArgumentError
      redirect_to admin_broadcast_path(@recording), alert: "Enter a valid recording offset."
    end

    def discover
      Warehouse::Broadcasts::DiscoverJob.perform_later
      redirect_to admin_broadcasts_path, notice: "CPAC discovery queued."
    end

    def toggle
      stream = Warehouse::MediaStream.where.not(kind: "on_demand").find(params[:id])
      state = MediaCaptureState.find_or_create_by!(media_stream_id: stream.id)
      state.with_lock do
        state.update!(enabled: !state.enabled?, next_poll_at: Time.current,
          lease_token: nil, lease_expires_at: nil)
      end
      Warehouse::Broadcasts::CaptureJob.perform_later(stream.id) if state.enabled?
      redirect_to admin_broadcasts_path, notice: "Capture #{state.enabled? ? 'enabled' : 'paused'}."
    end

    def playlist
      audio = selected_audio
      playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: audio, at: parse_offset(params[:at]))
      body = playback.playlist(gap_url: gap_admin_broadcasts_url)
      return head :not_found unless body

      response.headers["Cache-Control"] = "private, no-store"
      render plain: body, content_type: "application/vnd.apple.mpegurl"
    rescue ArgumentError => error
      render plain: error.message, status: :unprocessable_entity
    end

    def captions
      track = @recording.stream.tracks.where(kind: "captions").find(params[:track_id])
      playback = Warehouse::Broadcasts::Playback.new(@recording, audio_track: selected_audio, at: parse_offset(params[:at]))
      body = Warehouse::Broadcasts::CaptionPresentation.new(track, starts_at: playback.starts_at, ends_at: playback.ends_at).call
      response.headers["Cache-Control"] = "private, max-age=30"
      render plain: body, content_type: "text/vtt"
    end

    def subtitle_cues
      passage = Warehouse::MediaTranscriptPassage.published
        .where(media_track_id: @recording.stream.tracks.where(kind: "captions").select(:id)).find(params[:passage_id])
      starts_at = [ passage.starts_at, @recording.starts_at ].max
      ends_at = [ passage.ends_at, @recording.ends_at ].compact.min
      return head :not_found unless ends_at > starts_at

      body = Warehouse::Broadcasts::CaptionPresentation.new(passage.track, starts_at:, ends_at:).call
      cues = Warehouse::Broadcasts::WebVtt.parse(body).first(500).map do |cue|
        { text: cue.text, start: (starts_at - @recording.starts_at + cue.start_seconds).round(3),
          end: (starts_at - @recording.starts_at + cue.end_seconds).round(3) }
      end
      query = params[:q].to_s.strip.first(500)
      if query.present?
        segments = Warehouse::MediaTranscriptPassage.transaction(requires_new: true) do
          Warehouse::Broadcasts::TranscriptSearch.highlight_segments(texts: cues.map { |cue| cue[:text] }, query:)
        end
        cues.zip(segments).each { |cue, highlight| cue[:segments] = highlight }
      end
      render json: { cues: }
    rescue ActiveRecord::StatementInvalid => error
      Rails.error.report(error)
      render json: { error: "Subtitle highlighting is temporarily unavailable." }, status: :unprocessable_entity
    rescue Aws::S3::Errors::ServiceError => error
      Rails.error.report(error)
      render json: { error: "Subtitle files are temporarily unavailable." }, status: :service_unavailable
    end

    def gap
      head :not_found
    end

    private

    def prepare_editor_timeline
      coverage = @recording.stream.objects.current_playback
        .where("metadata ->> 'audio_track_id' IS NOT DISTINCT FROM ?", @audio_track&.id&.to_s)
        .where("ends_at > ?", @recording.starts_at)
      coverage = coverage.where("starts_at < ?", @recording.ends_at) if @recording.ends_at
      ranges = coverage.order(:starts_at).pluck(:starts_at, :ends_at).map do |from, to|
        [ [ from - @recording.starts_at, 0 ].max,
          [ to, @recording.ends_at ].compact.min - @recording.starts_at ]
      end
      @available_end = ranges.map(&:last).max || 0
      @editor_window_end = [ @playback.ends_at - @recording.starts_at, @available_end ].min
      cursor = 0
      @editor_gaps = ranges.filter_map do |from, to|
        gap = [ cursor.round(3), from.round(3) ] if from > cursor + 0.05
        cursor = [ cursor, to ].max
        gap
      end
    end

    def set_recording
      @recording = Warehouse::MediaRecording.find(params[:id])
    end

    def selected_audio
      tracks = @recording.stream.tracks.where(kind: "audio").order(last_seen_at: :desc, id: :desc)
      return tracks.find(params[:audio_track_id]) if params[:audio_track_id].present?

      default_audio(tracks, at: parse_offset(params[:at]))
    end

    def default_audio(tracks, at:)
      ids = @recording.stream.objects.current_playback
        .where("starts_at < ? AND ends_at > ?", at + 30.minutes, at - 2.minutes)
        .distinct.pluck(Arel.sql("metadata ->> 'audio_track_id'")).compact
      available = ids.any? ? tracks.where(id: ids) : tracks
      available.find_by(language: "en") || available.first
    end

    def parse_offset(value)
      seconds = value.present? ? Float(value) : 0
      raise ArgumentError unless seconds.finite? && seconds >= 0 && seconds <= 7.days
      raise ArgumentError if @recording.ends_at && seconds >= @recording.ends_at - @recording.starts_at

      @recording.starts_at + seconds
    end

    def clip_offset(value, fallback:)
      return fallback unless value.present?

      offset = Float(value)
      raise ArgumentError unless offset.finite? && offset >= 0 && offset <= 7.days

      offset
    end

    def search_passages
      language = params[:language].in?(%w[en fr]) ? params[:language] : "en"
      relation = Warehouse::Broadcasts::TranscriptSearch.new(query: params[:q].to_s.first(500), language:,
        stream_id: params[:stream_id], starts_at: @filter_date&.beginning_of_day,
        ends_at: @filter_date&.next_day&.beginning_of_day).ranked.includes(track: :media_stream)
      Warehouse::MediaTranscriptPassage.transaction(requires_new: true) do
        @search_pagy, passages = pagy(:offset, relation, limit: 50, page_key: "search_page")
        @hits = passages.filter_map do |passage|
          recording = passage.stream.recordings.where("starts_at <= ? AND (ends_at IS NULL OR ends_at > ?)", passage.starts_at, passage.starts_at).order(starts_at: :desc).first
          [ passage, recording ] if recording
        end
      end
    rescue ActiveRecord::StatementInvalid => error
      Rails.error.report(error)
      @hits = []
      @search_error = if Warehouse::Broadcasts::TranscriptSearch.query_error?(error)
        "That transcript query is not valid. Check quotes, parentheses, and search operators."
      else
        "Transcript search is temporarily unavailable. Recording transcripts remain available."
      end
    end

    def load_transcript_passages(scope)
      Warehouse::MediaTranscriptPassage.transaction(requires_new: true) do
        @transcript_pagy, passages = pagy(:offset, scope.includes(:track), limit: 50,
          page_key: "transcript_page")
        @passages = passages.load
      end
    rescue ActiveRecord::StatementInvalid => error
      Rails.error.report(error)
      @transcript_search_error = if Warehouse::Broadcasts::TranscriptSearch.query_error?(error)
        "That subtitle query is not valid. Check quotes, parentheses, and search operators."
      else
        "Subtitle search is temporarily unavailable. Playback and clipping remain available."
      end
      @transcript_pagy, @passages = pagy(:offset, Warehouse::MediaTranscriptPassage.none, limit: 50,
        page_key: "transcript_page")
    end
  end
end
