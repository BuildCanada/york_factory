module Usage
  # The 80% and 100% quota emails (Usage::QuotaNotices). Usage::RollupJob
  # runs them after every rollup; this job is for running them alone.
  class QuotaNoticeJob < ApplicationJob
    queue_as :default

    def perform = QuotaNotices.new.run!
  end
end
