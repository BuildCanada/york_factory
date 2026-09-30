module Billing
  # Where Billing::ReportUsageJob sends usage records. Only NullReporter
  # exists: it reports nothing, so records stay pending. A Stripe reporter
  # would send each record as a Billing Meter event
  # (event_name "api_units", payload stripe_customer_id and value units,
  # identifier the record's idempotency_key) and return the event's ID.
  #
  #   Billing::Reporter.current = Billing::StripeReporter.new   # later
  module Reporter
    class NullReporter
      # The external ID of the reported record, or nil if it wasn't sent.
      def report(_record) = nil
    end

    class << self
      attr_writer :current

      def current = @current ||= NullReporter.new
    end
  end
end
