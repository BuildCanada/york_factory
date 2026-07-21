# Polls election candidate sources (election_*) on their own fetch_frequency,
# mirroring FetchEconomySourcesJob. Scheduled daily (config/recurring.yml);
# candidate lists churn during the nomination window and go quiet after, and
# checksum dedupe in Source::Fetcher makes unchanged fetches no-ops either
# way. Manual sources are never auto-fetched.
class Warehouse::FetchElectionSourcesJob < ApplicationJob
  queue_as :default

  INTERVALS = {
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month,
    "quarterly" => 3.months,
    "annual" => 1.year
  }.freeze

  # Grace subtracted from the interval so scheduler drift (the daily run
  # never fires at exactly the same instant) can't push a source's next
  # fetch a whole day late.
  GRACE = 12.hours

  def perform
    Warehouse::Source.where("name LIKE 'election\\_%'").find_each do |source|
      interval = INTERVALS[source.fetch_frequency]
      next if interval.nil? || !due?(source, interval)

      source.fetcher.fetch_later
    end
  end

  private

  def due?(source, interval)
    source.last_fetched_at.nil? || source.last_fetched_at <= (interval - GRACE).ago
  end
end
