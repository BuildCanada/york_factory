require "test_helper"

class Warehouse::FetchElectionSourcesJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def create_source(name:, frequency:, last_fetched_at: nil)
    Warehouse::Source.create!(
      name: name,
      url: "https://example.com/#{name}",
      format: "toronto_candidates_json",
      fetch_frequency: frequency,
      last_fetched_at: last_fetched_at
    )
  end

  test "fetches never-fetched and due election sources" do
    create_source(name: "election_never_fetched_2026", frequency: "daily")
    create_source(name: "election_due_daily_2026", frequency: "daily", last_fetched_at: 2.days.ago)

    assert_enqueued_jobs 2, only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchElectionSourcesJob.perform_now
    end
  end

  test "skips sources fetched within their frequency interval" do
    create_source(name: "election_fresh_daily_2026", frequency: "daily", last_fetched_at: 4.hours.ago)

    assert_no_enqueued_jobs only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchElectionSourcesJob.perform_now
    end
  end

  test "never fetches manual or non-election sources" do
    create_source(name: "election_manual_2026", frequency: "manual")
    create_source(name: "econ_not_an_election", frequency: "daily", last_fetched_at: 1.year.ago)

    assert_no_enqueued_jobs only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchElectionSourcesJob.perform_now
    end
  end
end
