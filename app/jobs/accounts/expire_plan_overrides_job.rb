module Accounts
  # Clears plan overrides whose expiry has passed and pushes the accounts'
  # keys to the edge, so the Worker enforces the plan's own rate and quota at
  # once rather than when its 5-minute lookup cache runs out (design §4.5:
  # "plan overrides with expiry. Changes push to the AccountDO at once").
  class ExpirePlanOverridesJob < ApplicationJob
    queue_as :default

    def perform(now: Time.current)
      Account.where.not(plan_override: nil).where(plan_override_expires_at: ..now).find_each do |account|
        before = account.plan_override
        account.update!(plan_override: nil, plan_override_expires_at: nil)
        AuditEvent.record!("account.plan_override_expired", context: AuditEvent::Context.system, account:, subject: account,
          metadata: { plan_override: before, plan: account.plan })
        Edge::Push.account(account)
      end
    end
  end
end
