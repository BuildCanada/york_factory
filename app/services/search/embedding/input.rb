require "digest"

module Search
  module Embedding
    class Input
      OMISSION_MARKER = "\n\n[... content omitted ...]\n\n"
      HEAD_RATIO = 0.75

      Prepared = Data.define(:text, :hash, :scope, :estimated_tokens, :original_characters)

      def initialize(max_characters: ProviderConfig.cohere_max_input_characters)
        raise ArgumentError, "max_characters must be positive" unless max_characters.is_a?(Integer) && max_characters.positive?

        @max_characters = max_characters
      end

      def prepare(text)
        normalized = text.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�").strip
        raise ArgumentError, "embedding input is empty" if normalized.blank?

        scope = normalized.length <= @max_characters ? "full" : "truncated"
        bounded = scope == "full" ? normalized : truncate(normalized)
        Prepared.new(
          text: bounded,
          hash: Digest::SHA256.hexdigest(bounded),
          scope: scope,
          estimated_tokens: estimate_tokens(bounded),
          original_characters: normalized.length
        )
      end

      private

      def truncate(text)
        available = @max_characters - OMISSION_MARKER.length
        raise ArgumentError, "max_characters is too small for the omission marker" unless available.positive?

        head_length = (available * HEAD_RATIO).floor
        tail_length = available - head_length
        "#{text[0, head_length]}#{OMISSION_MARKER}#{text[-tail_length, tail_length]}"
      end

      # Azure returns authoritative usage after the request. This estimate exists
      # only for providers or responses that omit token telemetry.
      def estimate_tokens(text)
        [ (text.length / 4.0).ceil, 1 ].max
      end
    end
  end
end
