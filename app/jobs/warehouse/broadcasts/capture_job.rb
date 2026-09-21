module Warehouse
  module Broadcasts
    class CaptureJob < ApplicationJob
      include ActiveJob::Continuable

      LEASE_TTL = 2.minutes
      EVENT_STALE_AFTER = 10.minutes
      MIN_POLL = 2.seconds
      MAX_POLL = 15.seconds

      retry_on HttpClient::TransientError, Hls::ParseError, wait: :polynomially_longer, attempts: 6

      def perform(media_stream_id)
        state = MediaCaptureState.find_by(media_stream_id:)
        return unless state
        return unless state.enabled?

        token = state.claim!(now: Time.current, ttl: LEASE_TTL)
        return unless token

        if stale_event?(state)
          reason = "event_missing_from_discovery_for_#{EVENT_STALE_AFTER.to_i}_seconds"
          capturer.finalize_stale!(stream: state.media_stream, state:, lease_token: token, reason:)
          state.release_lease!(token:, now: Time.current, attrs: {
            enabled: false, next_poll_at: nil, consecutive_failures: 0, last_error: nil
          })
          ProcessJob.perform_later(state.media_stream_id)
          return
        end

        if prelive_wait?(state.media_stream)
          next_poll = [ state.media_stream.scheduled_start_at - 30.seconds, Time.current + MAX_POLL ].max
          state.release_lease!(token:, now: Time.current, attrs: { next_poll_at: next_poll })
          self.class.set(wait_until: next_poll).perform_later(state.media_stream_id)
          return
        end

        step :capture do |step|
          result = capturer.call(stream: state.media_stream, state:, lease_token: token) do |identity|
            step.set!(identity)
          end
          ProcessJob.perform_later(state.media_stream_id) if result.captured_count.positive? || result.end_list
          next_poll = Time.current + result.target_duration.clamp(MIN_POLL.to_f, MAX_POLL.to_f)
          state.release_lease!(token:, now: Time.current, attrs: {
            enabled: !result.end_list, next_poll_at: result.end_list ? nil : next_poll,
            consecutive_failures: 0, last_error: nil
          })
          self.class.set(wait_until: next_poll).perform_later(state.media_stream_id) unless result.end_list
        end
      rescue HttpClient::PermanentError, Hls::UnsupportedTransport => error
        state&.release_lease!(token:, now: Time.current, attrs: {
          enabled: false, next_poll_at: nil,
          consecutive_failures: state.consecutive_failures.to_i + 1,
          last_error: "#{error.class}: #{error.message}".truncate(2_000)
        }) if token
      rescue StandardError => error
        state&.release_lease!(token:, now: Time.current, attrs: {
          next_poll_at: Time.current + retry_delay(state),
          consecutive_failures: state.consecutive_failures.to_i + 1,
          last_error: "#{error.class}: #{error.message}".truncate(2_000)
        }) if token
        raise
      ensure
        state&.release_lease!(token:, now: Time.current) if token
      end

      private

      def capturer
        @capturer ||= Capturer.new
      end

      def retry_delay(state)
        [ 2**state.consecutive_failures.to_i, 5.minutes.to_i ].min.seconds
      end

      def prelive_wait?(stream)
        stream.provider_state == "prelive" && stream.scheduled_start_at && stream.scheduled_start_at > Time.current + 30.seconds
      end

      def stale_event?(state)
        stream = state.media_stream
        stream.kind == "event" && state.last_captured_at.present? &&
          stream.last_seen_at < EVENT_STALE_AFTER.ago && state.last_captured_at < EVENT_STALE_AFTER.ago
      end
    end
  end
end
