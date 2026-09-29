module Usage
  # Daily: yesterday's rolled-up units against the edge's AccountDO
  # (Usage::Reconcile). Does nothing without EDGE_URL.
  class ReconcileJob < ApplicationJob
    queue_as :default

    def perform(day: nil) = Reconcile.new.run!(**(day ? { day: Date.iso8601(day.to_s) } : {}))
  end
end
