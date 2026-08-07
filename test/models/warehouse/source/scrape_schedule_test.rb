require "test_helper"

class Warehouse::Source::ScrapeScheduleTest < ActiveSupport::TestCase
  setup do
    @schedule = Warehouse::Source::ScrapeSchedule.new
    @from = Time.zone.parse("2026-08-06 08:00")
  end

  test "uses the next economy cron occurrence rather than last fetched time" do
    source = source_named("econ_gdp", frequency: "weekly", last_fetched_at: 2.days.ago)

    assert_equal Time.zone.parse("2026-08-07 07:00"), @schedule.next_run_at(source, from: @from)
    assert_equal "every day at 7am", @schedule.schedule_for(source)
  end

  test "uses each source group's production cron" do
    spending = source_named("spending_contracts", frequency: "daily")
    election = source_named("election_toronto", frequency: "daily")

    assert_equal Time.zone.parse("2026-08-07 07:30"), @schedule.next_run_at(spending, from: @from)
    assert_equal Time.zone.parse("2026-08-07 00:00"), @schedule.next_run_at(election, from: @from)
  end

  test "manual and unscheduled sources have no next cron occurrence" do
    manual = source_named("econ_manual", frequency: "manual")
    unscheduled = source_named("other_source", frequency: "daily")

    assert_nil @schedule.next_run_at(manual, from: @from)
    assert_nil @schedule.next_run_at(unscheduled, from: @from)
  end

  private

  def source_named(name, frequency:, last_fetched_at: nil)
    Warehouse::Source.new(name:, fetch_frequency: frequency, last_fetched_at:)
  end
end
