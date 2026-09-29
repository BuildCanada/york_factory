module Developers
  # The developer console (docs/public-interface-design.md §4.4), served at
  # /developers beside the Doorkeeper login on auth.buildcanada.com. It
  # replaces /profile/api_keys.
  class BaseController < ActionController::Base
    layout "profile"

    before_action :require_login!
    before_action :set_account

    helper_method :current_account, :current_membership, :can_manage_keys?, :accounts_for_switcher

    private

    def require_login!
      redirect_to new_user_session_path unless user_signed_in?
    end

    def set_account
      @account = selected_account || Account.personal_for!(current_user)
      @membership = @account.membership_for(current_user)
    end

    def selected_account
      return if session[:developer_account_id].blank?

      current_user.accounts.find_by(id: session[:developer_account_id])
    end

    def current_account = @account

    def current_membership = @membership

    def can_manage_keys? = @membership&.manages_keys? || false

    def accounts_for_switcher = current_user.accounts.order(:kind, :name)

    def require_key_manager!
      redirect_to developers_keys_path, alert: "Only account owners and admins can change keys." unless can_manage_keys?
    end

    def audit_context = AuditEvent::Context.from_request(request, actor: current_user)
  end
end
