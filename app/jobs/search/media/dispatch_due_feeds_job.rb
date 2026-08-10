module Search
  module Media
    class DispatchDueFeedsJob < ApplicationJob
      BATCH_SIZE = 100

      def perform(at: Time.current)
        claimed_ids = []

        Warehouse::MediaFeed.transaction do
          Warehouse::MediaFeed.due(at)
            .order(:next_fetch_at, :id)
            .limit(BATCH_SIZE)
            .lock("FOR UPDATE SKIP LOCKED")
            .each do |feed|
              feed.update!(next_fetch_at: at + feed.cadence_seconds.seconds)
              claimed_ids << feed.id
            end
        end

        claimed_ids.each { |feed_id| FetchFeedJob.perform_later(feed_id) }
      end
    end
  end
end
