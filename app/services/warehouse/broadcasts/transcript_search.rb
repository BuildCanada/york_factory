module Warehouse
  module Broadcasts
    class TranscriptSearch
      LANGUAGES = %w[en fr].freeze
      QUERY_ERROR_PATTERN = /invalid ==> query|TIN(?:QL| score)? query error|invalid TINQL/i
      PASSAGES = '"warehouse"."media_transcript_passages"'.freeze
      TRACKS = '"warehouse"."media_tracks"'.freeze
      HIGHLIGHT_START = "\u{FDD0}tin-highlight-start\u{FDD1}".freeze
      HIGHLIGHT_END = "\u{FDD0}tin-highlight-end\u{FDD1}".freeze

      def self.query_error?(error)
        error_chain = Enumerator.produce(error, &:cause).take_while(&:present?)
        error_chain.any? { |item| item.message.match?(QUERY_ERROR_PATTERN) }
      end

      def self.segments(passage = nil, text: nil, highlighted_text: nil)
        if passage
          text = passage.text
          highlighted_text = passage.highlighted_text if passage.has_attribute?(:highlighted_text)
        end
        text = text.to_s
        return [ { text:, match: false } ] if highlighted_text.nil?

        highlighted_text = highlighted_text.to_s
        segments = []
        matching = false
        reconstructed = +""
        marker_pattern = /(#{Regexp.escape(HIGHLIGHT_START)}|#{Regexp.escape(HIGHLIGHT_END)})/

        return [ { text:, match: false } ] if text.include?(HIGHLIGHT_START) || text.include?(HIGHLIGHT_END)

        highlighted_text.split(marker_pattern, -1).each do |part|
          if part == HIGHLIGHT_START
            return [ { text:, match: false } ] if matching
            matching = true
          elsif part == HIGHLIGHT_END
            return [ { text:, match: false } ] unless matching
            matching = false
          else
            reconstructed << part
            append_segment(segments, part, matching)
          end
        end
        return [ { text:, match: false } ] if matching || reconstructed != text

        segments.presence || [ { text: "", match: false } ]
      end

      def self.highlight_segments(texts:, query:)
        texts = Array(texts).map(&:to_s)
        query = query.to_s.strip
        return texts.map { |text| [ { text:, match: false } ] } if query.blank? || texts.empty?

        connection = Warehouse::MediaTranscriptPassage.connection
        bindings = [ HIGHLIGHT_START, HIGHLIGHT_END, query, texts.to_json ].map.with_index do |value, index|
          ActiveRecord::Relation::QueryAttribute.new("highlight_#{index}", value, ActiveRecord::Type::String.new)
        end
        sql = <<~SQL
          SELECT input.position,
                 tin.highlight(input.text, $1::text, $2::text, $3::text) AS highlighted_text
          FROM jsonb_array_elements_text($4::jsonb) WITH ORDINALITY AS input(text, position)
          ORDER BY input.position
        SQL

        connection.select_rows(sql, "Subtitle highlights", bindings).map.with_index do |(_position, highlighted_text), index|
          segments(text: texts.fetch(index), highlighted_text:)
        end
      end

      def initialize(query:, language: nil, recording: nil, stream_id: nil, starts_at: nil, ends_at: nil)
        @query = query.to_s.strip
        @language = language.presence_in(LANGUAGES)
        @recording = recording
        @stream_id = stream_id.presence
        @starts_at = starts_at
        @ends_at = ends_at
      end

      def ranked
        matching
          .select("#{PASSAGES}.*, tin.score(#{PASSAGES}.ctid) AS search_score, #{highlight_sql}")
          .order(Arel.sql("search_score DESC, #{PASSAGES}.starts_at DESC, #{PASSAGES}.id DESC"))
      end

      def chronological
        matching
          .select("#{PASSAGES}.*, #{highlight_sql}")
          .order(Arel.sql("#{PASSAGES}.starts_at, #{PASSAGES}.media_track_id, #{PASSAGES}.id"))
      end

      private

      def self.append_segment(segments, value, matching)
        return if value.empty?

        if segments.last&.fetch(:match) == matching
          segments.last[:text] << value
        else
          segments << { text: value, match: matching }
        end
      end
      private_class_method :append_segment

      def matching
        raise ArgumentError, "query must be present" if @query.blank?

        # Keep the publication predicate literal so PostgreSQL can prove that the
        # query is eligible for the partial TIN index.
        scope = Warehouse::MediaTranscriptPassage
          .joins("INNER JOIN #{TRACKS} ON #{TRACKS}.id = #{PASSAGES}.media_track_id")
          .where("#{PASSAGES}.state = 'published'")
          .where("#{TRACKS}.kind = 'captions'")
          .where("#{PASSAGES}.text ==> ?", @query)
        scope = scope.where("#{TRACKS}.language = ?", @language) if @language

        stream_id = @recording&.media_stream_id || @stream_id
        scope = scope.where("#{TRACKS}.media_stream_id = ?", stream_id) if stream_id

        starts_at = @recording&.starts_at || @starts_at
        ends_at = @recording&.ends_at || @ends_at
        scope = scope.where("#{PASSAGES}.ends_at > ?", starts_at) if starts_at
        scope = scope.where("#{PASSAGES}.starts_at < ?", ends_at) if ends_at
        scope
      end

      def highlight_sql
        Warehouse::MediaTranscriptPassage.send(:sanitize_sql_array, [
          "tin.highlight(#{PASSAGES}.text, ?, ?, ?) AS highlighted_text",
          HIGHLIGHT_START,
          HIGHLIGHT_END,
          @query
        ])
      end
    end
  end
end
