module Billing
  # Daily: writes the usage records of complete days (old enough that the
  # hourly rollup's 48-hour window no longer changes them) and sends pending
  # ones through Billing::Reporter. With the NullReporter nothing is sent.
  class ReportUsageJob < ApplicationJob
    queue_as :default

    SETTLED_AFTER = 3

    def perform(day: nil)
      day = day ? Date.iso8601(day.to_s) : Time.current.utc.to_date - SETTLED_AFTER
      UsageRecords.new.build!(day:)
      UsageRecord.pending.where(period_start: ..day).includes(:account).find_each do |record|
        external_id = Reporter.current.report(record) or next

        record.update!(status: "reported", external_id:, reported_at: Time.current)
      end
    end
  end
end
