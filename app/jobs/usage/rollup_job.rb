module Usage
  # Pulls the edge's Analytics Engine points into usage_hourly and
  # usage_daily (Usage::Rollup), then sends any quota emails that crossing
  # 80% or 100% calls for. Scheduled every minute over the last 2 hours and
  # hourly over the last 48 (config/recurring.yml). Does nothing without
  # Analytics Engine credentials.
  class RollupJob < ApplicationJob
    queue_as :default
    limits_concurrency key: ->(*) { "usage_rollup" }, to: 1, duration: 10.minutes

    def perform(window_hours = 48)
      result = Rollup.new.run!(window: window_hours.to_i.hours)
      QuotaNotices.new.run! if result
      result
    end
  end
end
