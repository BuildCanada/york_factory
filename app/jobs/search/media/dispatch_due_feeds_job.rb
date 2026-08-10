module Search
  module Media
    class DispatchDueFeedsJob < ApplicationJob
      BATCH_SIZE = 100
      HOST_SPACING = 5.seconds

      def perform(at: Time.current)
        claimed_feeds = []

        Warehouse::MediaFeed.transaction do
          Warehouse::MediaFeed.due(at)
            .order(:next_fetch_at, :id)
            .limit(BATCH_SIZE)
            .lock("FOR UPDATE SKIP LOCKED")
            .each do |feed|
              feed.update!(next_fetch_at: at + feed.cadence_seconds.seconds)
              claimed_feeds << [ feed.id, feed.publisher_domain ]
            end
        end

        host_counts = Hash.new(0)
        claimed_feeds.each do |feed_id, publisher_domain|
          delay = host_counts[publisher_domain] * HOST_SPACING
          host_counts[publisher_domain] += 1

          if delay.zero?
            FetchFeedJob.perform_later(feed_id)
          else
            FetchFeedJob.set(wait: delay).perform_later(feed_id)
          end
        end
      end
    end
  end
end
