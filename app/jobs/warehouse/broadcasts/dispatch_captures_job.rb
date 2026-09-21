module Warehouse
  module Broadcasts
    class DispatchCapturesJob < ApplicationJob
      BATCH_SIZE = 50

      def perform
        now = Time.current
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
