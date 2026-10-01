module Warehouse
  module Broadcasts
    class DispatchCapturesJob < ApplicationJob
      BATCH_SIZE = 50

      def perform
        now = Time.current
        MediaCaptureState.where(enabled: false, next_poll_at: nil).where.not(last_error: nil)
          .where("lease_expires_at IS NULL OR lease_expires_at <= ?", now)
          .where(media_stream_id: Warehouse::MediaStream.where(provider: "cpac", kind: %w[event continuous]).select(:id))
          .where("last_error LIKE ? OR last_error LIKE ?", "%: HTTP 404 for https://%", "%: host did not resolve")
          .order(:id).limit(BATCH_SIZE).each { |state| state.recover_transport_failure!(now:) }
        MediaCaptureState.where(enabled: true)
          .where.not(media_stream_id: Warehouse::MediaStream.where(kind: "on_demand").select(:id))
          .where("next_poll_at IS NULL OR next_poll_at <= ?", now)
          .where("lease_expires_at IS NULL OR lease_expires_at <= ?", now)
          .order(Arel.sql("next_poll_at NULLS FIRST"), :id)
          .limit(BATCH_SIZE)
          .pluck(:media_stream_id)
          .each { |stream_id| CaptureJob.perform_later(stream_id) }
      end
    end
  end
end
