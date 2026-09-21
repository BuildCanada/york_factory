module Warehouse
  module Broadcasts
    class HistoricalCaptureJob < ApplicationJob
      self.enqueue_after_transaction_commit = true
      LEASE_TTL = 2.minutes
      SEGMENT_LIMIT = 100
      MAX_TRANSIENT_FAILURES = 6

      def perform(media_stream_id, backfill_item_id)
        item = BroadcastBackfillItem.find(backfill_item_id)
        stream = MediaStream.find(media_stream_id)
        raise ArgumentError, "backfill item does not belong to stream" unless item.media_stream_id == stream.id
        unless stream.provider == "cpac" && stream.kind == "on_demand"
          raise ArgumentError, "historical capture requires an on-demand CPAC stream"
        end
        return unless item.state.in?(%w[queued running])
        return item.mark_completed! if capture_complete?(stream)

        state = MediaCaptureState.find_or_create_by!(media_stream_id:) do |new_state|
          new_state.enabled = true
          new_state.next_poll_at = Time.current
        end
        unless state.enabled?
          state.update!(enabled: true, next_poll_at: Time.current, consecutive_failures: 0, last_error: nil)
        end
        token = state.claim!(now: Time.current, ttl: LEASE_TTL)
        unless token
          wait_until = state.reload.next_poll_at || 10.seconds.from_now
          self.class.set(wait_until: [ wait_until, 1.second.from_now ].max)
            .perform_later(media_stream_id, backfill_item_id)
          return
        end

        item.mark_running!
        result = capturer.call(stream:, state:, lease_token: token, limit: SEGMENT_LIMIT, source: :historical)
        if result.end_list
          ProcessJob::BacklogJob.set(wait: 1.second).perform_later(media_stream_id)
        elsif result.captured_count.positive?
          ProcessJob.perform_later(media_stream_id)
        end
        if result.end_list
          state.release_lease!(token:, now: Time.current, attrs: {
            enabled: false, next_poll_at: nil, consecutive_failures: 0, last_error: nil
          })
          complete_items(stream)
        else
          state.release_lease!(token:, now: Time.current, attrs: {
            enabled: true, next_poll_at: Time.current, consecutive_failures: 0, last_error: nil
          })
          self.class.perform_later(media_stream_id, backfill_item_id)
        end
      rescue Hls::UnsupportedTransport => error
        fail_capture(state:, token:, item:, error:)
      rescue HttpClient::TransientError, Hls::ParseError => error
        failures = state.consecutive_failures.to_i + 1
        if failures >= MAX_TRANSIENT_FAILURES
          fail_capture(state:, token:, item:, error:, failures:)
        else
          retry_at = Time.current + [ 2**failures, 5.minutes.to_i ].min.seconds
          state&.release_lease!(token:, now: Time.current, attrs: {
            enabled: true, next_poll_at: retry_at, consecutive_failures: failures,
            last_error: "#{error.class}: #{error.message}".truncate(2_000)
          }) if token
          item&.update!(state: "queued", error: "Retrying: #{error.message}".truncate(2_000), queued_at: retry_at)
          self.class.set(wait_until: retry_at).perform_later(media_stream_id, backfill_item_id)
        end
      rescue Capturer::LeaseLost
        item&.update!(state: "queued")
        self.class.set(wait: 10.seconds).perform_later(media_stream_id, backfill_item_id)
      rescue StandardError => error
        fail_capture(state:, token:, item:, error:)
      ensure
        state&.release_lease!(token:, now: Time.current) if token
      end

      private

      def capturer
        @capturer ||= Capturer.new
      end

      def capture_complete?(stream)
        stream.recordings.any? { |recording| recording.metadata["capture_complete"] == true }
      end

      def complete_items(stream)
        BroadcastBackfillItem.where(media_stream: stream, state: %w[queued running]).find_each(&:mark_completed!)
      end

      def fail_capture(state:, token:, item:, error:, failures: nil)
        state&.release_lease!(token:, now: Time.current, attrs: {
          enabled: false, next_poll_at: nil,
          consecutive_failures: failures || state.consecutive_failures.to_i + 1,
          last_error: "#{error.class}: #{error.message}".truncate(2_000)
        }) if token
        item&.mark_failed!(error)
      end
    end
  end
end
