module Warehouse
  module Broadcasts
    class RecoverBackfillsJob < ApplicationJob
      BATCH_SIZE = 100
      CAPTURE_STALE_AFTER = 10.minutes

      def perform
        BroadcastBackfillRequest.where(state: %w[queued running])
          .where("lease_expires_at IS NULL OR lease_expires_at <= ?", Time.current)
          .limit(BATCH_SIZE).find_each(&:recover!)

        BroadcastBackfillItem.where(state: %w[queued running])
          .where("broadcast_backfill_items.updated_at <= ?", CAPTURE_STALE_AFTER.ago)
          .limit(BATCH_SIZE).includes(:media_stream).find_each do |item|
          state = item.media_stream.media_capture_state
          next if state&.lease_expires_at&.future?

          item.with_lock do
            next unless item.state.in?(%w[queued running]) && item.updated_at <= CAPTURE_STALE_AFTER.ago

            item.update!(queued_at: Time.current)
            HistoricalCaptureJob.perform_later(item.media_stream_id, item.id)
          end
        end
      end
    end
  end
end
