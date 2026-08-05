module Search
  module Media
    class DispatchDueSourcesJob < ApplicationJob
      BATCH_SIZE = 100

      def perform(at: Time.current)
        claimed_ids = []

        Search::Source.transaction do
          Search::Source.due(at)
            .where(realm: "media", strategy: %w[rss atom])
            .order(:next_fetch_at, :id)
            .limit(BATCH_SIZE)
            .lock("FOR UPDATE SKIP LOCKED")
            .each do |source|
              source.update!(next_fetch_at: at + source.cadence_seconds.seconds)
              claimed_ids << source.id
            end
        end

        claimed_ids.each { |source_id| FetchSourceJob.perform_later(source_id) }
      end
    end
  end
end
