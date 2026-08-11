class Warehouse::FetchSpendingSourcesJob < ApplicationJob
  queue_as :default

  INTERVALS = Warehouse::Source::SCRAPE_INTERVALS
  GRACE = 12.hours

  def perform
    Warehouse::Source.where("name LIKE 'spending\\_%'").find_each do |source|
      interval = INTERVALS[source.fetch_frequency]
      next if interval.nil?
      next if source.last_fetched_at && source.last_fetched_at > (interval - GRACE).ago

      source.fetcher.fetch_later
    end
  end
end
