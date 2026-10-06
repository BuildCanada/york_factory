module Oauth
  # Revokes an OAuth client's access to an account: every token and unused
  # authorization code it holds for that account (optionally only those one
  # user granted), at once. Audited as oauth.authorization_revoked.
  #
  #   Oauth::RevokeAuthorization.call(account:, application:, user: current_user, context:)
  class RevokeAuthorization
    def self.call(**) = new(**).call

    def initialize(account:, application:, context:, user: nil, now: Time.current)
      @account = account
      @application = application
      @user = user
      @context = context
      @now = now
    end

    def call
      tokens = Doorkeeper::AccessToken.where(account_id: @account.id, application_id: @application.id, revoked_at: nil)
      grants = Doorkeeper::AccessGrant.where(account_id: @account.id, application_id: @application.id, revoked_at: nil)
      if @user
        tokens = tokens.where(resource_owner_id: @user.id)
        grants = grants.where(resource_owner_id: @user.id)
      end

      ActiveRecord::Base.transaction do
        revoked = tokens.update_all(revoked_at: @now)
        grants.update_all(revoked_at: @now)
        AuditEvent.record!("oauth.authorization_revoked", context: @context, account: @account, subject: @application,
          metadata: { client_id: @application.uid, client_name: @application.name, tokens_revoked: revoked, user_id: @user&.id }.compact)
        revoked
      end
    end
  end
end
