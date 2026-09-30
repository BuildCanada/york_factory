module Developers
  # Apps (MCP clients and other OAuth clients) authorized to use the data API
  # for this account, with revoke (docs/public-interface-design.md §4.4).
  # Anyone can revoke an app they authorized; owners and admins can revoke
  # any app on the account.
  class AuthorizedAppsController < BaseController
    def index
      @entries = Oauth::AuthorizedApps.new(@account).entries
      @events = @account.audit_events.where("action LIKE 'oauth.%'").recent.includes(:actor_user).limit(50)
    end

    def destroy
      application = Doorkeeper::Application.public_api.find(params[:id])
      revoked = Oauth::RevokeAuthorization.call(account: @account, application:, user: (current_user unless can_manage_keys?),
        context: audit_context)
      notice = revoked.positive? ? "#{application.name} can no longer use this account. Its tokens stopped working at once." : "#{application.name} had no active access."
      redirect_to developers_authorized_apps_path, notice:
    end
  end
end
