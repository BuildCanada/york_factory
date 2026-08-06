class Warehouse::FetchSpendingSourcesJob < ApplicationJob
  queue_as :default

  INTERVALS = {
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month,
    "quarterly" => 3.months,
    "annual" => 1.year
  }.freeze
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
