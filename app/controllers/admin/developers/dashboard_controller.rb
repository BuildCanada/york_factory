module Admin
  module Developers
    class DashboardController < BaseController
      before_action :require_superadmin!, only: :mass_rotation

      def show
        @account_count = Account.count
        @suspended_count = Account.suspended.count
        @live_key_count = ApiKey.live.count
        @bifrost_key_count = ApiKey.live.bifrost.count
        @recently_used = ApiKey.live.where.not(last_used_at: nil).includes(:account).order(last_used_at: :desc).limit(10)
        @consumers = Usage::Consumers.new.top(limit: 25)
        @daily_units = Usage::Daily.where(day: (Time.current.utc.to_date - 29)..).group(:day).sum(:units)
        @rollup = Usage::RollupRun.latest
        @drifted = Usage::Reconciliation.drifted.where(day: (Time.current.utc.to_date - 7)..).includes(:account).order(day: :desc).limit(20)
        @reconciliation = AuditEvent.where(action: "admin.bifrost_reconciled").recent.first
        @mass_rotation = AuditEvent.where(action: "admin.mass_rotation").recent.first
      end

      def reconcile
        Keys::ReconcileBifrostJob.perform_later
        redirect_to admin_developers_root_path, notice: "Bifrost reconciliation queued."
      end

      # Every live Bifrost-issued key goes on a 7-day grace period and its
      # owners are asked to rotate it (Keys::MassRotateJob).
      def mass_rotation
        reason = params[:reason].to_s.strip
        if reason.blank? || params[:confirm] != "ROTATE ALL"
          redirect_to admin_developers_root_path, alert: "Give a reason and type ROTATE ALL to confirm."
          return
        end

        Keys::MassRotateJob.perform_later(reason:, actor_id: current_user.id)
        redirect_to admin_developers_root_path, notice: "Mass rotation queued."
      end
    end
  end
end
