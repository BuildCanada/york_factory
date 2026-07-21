require "test_helper"

class Warehouse::FetchEconomySourcesJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def create_source(name:, frequency:, last_fetched_at: nil)
    Warehouse::Source.create!(
      name: name,
      url: "https://example.com/#{name}",
      format: "csv",
      fetch_frequency: frequency,
      last_fetched_at: last_fetched_at
    )
  end

  test "fetches never-fetched and due econ sources" do
    create_source(name: "econ_never_fetched", frequency: "weekly")
    create_source(name: "econ_due_weekly", frequency: "weekly", last_fetched_at: 8.days.ago)
    create_source(name: "econ_due_monthly", frequency: "monthly", last_fetched_at: 5.weeks.ago)

    assert_enqueued_jobs 3, only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchEconomySourcesJob.perform_now
    end
  end

  test "skips sources fetched within their frequency interval" do
    create_source(name: "econ_fresh_weekly", frequency: "weekly", last_fetched_at: 2.days.ago)
    create_source(name: "econ_fresh_monthly", frequency: "monthly", last_fetched_at: 1.week.ago)

    assert_no_enqueued_jobs only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchEconomySourcesJob.perform_now
    end
  end

  test "allows scheduler drift within the grace window" do
    create_source(name: "econ_drifted", frequency: "weekly", last_fetched_at: (7.days - 6.hours).ago)

    assert_enqueued_jobs 1, only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchEconomySourcesJob.perform_now
    end
  end

  test "never fetches manual or non-econ sources" do
    create_source(name: "econ_manual", frequency: "manual")
    create_source(name: "infobase_something", frequency: "weekly", last_fetched_at: 1.year.ago)

    assert_no_enqueued_jobs only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchEconomySourcesJob.perform_now
    end
  end
end
