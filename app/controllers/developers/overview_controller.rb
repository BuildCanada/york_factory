module Developers
  class OverviewController < BaseController
    def show
      @plan = @account.plan_definition
      @live_keys = @account.api_keys.live.count
      @recent_events = @account.audit_events.recent.includes(:actor_user).limit(20)
      @quota = Usage::Quota.new(@account)
      @report = Usage::Report.new(account: @account)
    end
  end
end
