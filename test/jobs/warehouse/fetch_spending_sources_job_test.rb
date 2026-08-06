require "test_helper"

class Warehouse::FetchSpendingSourcesJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues only due automatic spending sources" do
    create_source("due", frequency: "weekly", last_fetched_at: 8.days.ago)
    create_source("fresh", frequency: "weekly", last_fetched_at: 1.day.ago)
    create_source("manual", frequency: "manual", last_fetched_at: nil)
    Warehouse::Source.create!(
      name: "econ_not_spending_#{SecureRandom.hex(4)}",
      url: "https://example.test/economy.csv",
      format: "csv",
      fetch_frequency: "weekly"
    )

    assert_enqueued_jobs 1, only: Warehouse::Source::Fetcher::FetchJob do
      Warehouse::FetchSpendingSourcesJob.perform_now
    end
  end

  private

  def create_source(suffix, frequency:, last_fetched_at:)
    Warehouse::Source.create!(
      name: "spending_#{suffix}_#{SecureRandom.hex(4)}",
      url: "https://example.test/#{suffix}.csv",
      format: "csv",
      fetch_frequency: frequency,
      last_fetched_at: last_fetched_at
    )
  end
end
