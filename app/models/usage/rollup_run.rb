module Usage
  # One Usage::Rollup run: the window it re-aggregated and when it finished.
  class RollupRun < ApplicationRecord
    self.table_name = "usage_rollup_runs"

    def self.latest = order(finished_at: :desc).first
  end
end
