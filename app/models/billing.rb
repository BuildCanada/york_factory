# The seam for metered billing (docs/public-interface-design.md §6.4). Only
# the records ship now: nothing calls Stripe.
module Billing
  def self.table_name_prefix = "billing_"
end
