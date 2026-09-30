module Admin
  module Developers
    class AccountsController < BaseController
      before_action :set_account, only: %i[show update suspend unsuspend]

      def index
        scope = Account.order(created_at: :desc)
        if params[:q].present?
          term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
          member_ids = AccountMembership.joins(:user).where("users.email ILIKE ? OR users.name ILIKE ?", term, term).select(:account_id)
          scope = scope.where("accounts.name ILIKE ?", term).or(scope.where(id: member_ids))
        end
        scope = scope.where(effective_plan_sql, params[:plan]) if params[:plan].in?(Plan::NAMES)
        scope = scope.suspended if params[:status] == "suspended"
        @pagy, @accounts = pagy(scope)
      end

      def show
        @memberships = @account.memberships.includes(:user).order(:role)
        @api_keys = @account.api_keys.order(created_at: :desc)
        @audit_events = @account.audit_events.recent.includes(:actor_user).limit(50)
      end

      # Plan and plan override (with optional expiry).
      def update
        before = @account.slice(:plan, :plan_override, :plan_override_expires_at)
        @account.assign_attributes(plan_params)
        @account.plan_override = nil if @account.plan_override.blank?
        @account.plan_override_expires_at = nil if @account.plan_override.nil?

        if @account.save
          if @account.saved_changes.except("updated_at").any?
            AuditEvent.record!("admin.plan_changed", context: audit_context, account: @account, subject: @account,
              metadata: { before: before.transform_values { |v| v.try(:iso8601) || v }, after: @account.slice(:plan, :plan_override, :plan_override_expires_at).transform_values { |v| v.try(:iso8601) || v } })
            Edge::Push.account(@account)
          end
          redirect_to admin_developers_account_path(@account), notice: "Plan updated."
        else
          show
          render :show, status: :unprocessable_entity
        end
      end

      def suspend
        reason = params[:reason].to_s.strip
        return redirect_to(admin_developers_account_path(@account), alert: "Give a reason for the suspension.") if reason.blank?

        @account.transaction do
          @account.update!(suspended_at: Time.current, suspended_reason: reason)
          AuditEvent.record!("admin.account_suspended", context: audit_context, account: @account, subject: @account, metadata: { reason: })
        end
        Edge::Push.account(@account)
        redirect_to admin_developers_account_path(@account), notice: "Account suspended. Its keys stop working at once."
      end

      def unsuspend
        @account.transaction do
          @account.update!(suspended_at: nil, suspended_reason: nil)
          AuditEvent.record!("admin.account_unsuspended", context: audit_context, account: @account, subject: @account)
        end
        Edge::Push.account(@account)
        redirect_to admin_developers_account_path(@account), notice: "Suspension lifted."
      end

      private

      def set_account
        @account = Account.find(params[:id])
      end

      def plan_params
        params.require(:account).permit(:plan, :plan_override, :plan_override_expires_at)
      end

      def effective_plan_sql
        "COALESCE(CASE WHEN accounts.plan_override_expires_at IS NULL OR accounts.plan_override_expires_at > now() " \
          "THEN accounts.plan_override END, accounts.plan) = ?"
      end
    end
  end
end
