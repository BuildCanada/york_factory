# Polls economy dashboard sources (econ_*) on their own fetch_frequency.
# Scheduled daily (config/recurring.yml); each run enqueues fetches only for
# sources whose interval has elapsed, so weekly, monthly, and quarterly
# sources coexist under one schedule. Manual sources are never auto-fetched.
# Checksum dedupe in Source::Fetcher makes unchanged fetches no-ops.
class Warehouse::FetchEconomySourcesJob < ApplicationJob
  queue_as :default

  INTERVALS = Warehouse::Source::SCRAPE_INTERVALS

  # Grace subtracted from the interval so scheduler drift (the daily run
  # never fires at exactly the same instant) can't push a source's next
  # fetch a whole day late.
  GRACE = 12.hours

  def perform
    Warehouse::Source.where("name LIKE 'econ\\_%'").find_each do |source|
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
