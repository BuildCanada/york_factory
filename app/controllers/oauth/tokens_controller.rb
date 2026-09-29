module Oauth
  # The token (POST /oauth/token) and revocation (POST /oauth/revoke,
  # RFC 7009) endpoints, extending Doorkeeper's for public-API tokens
  # (docs/public-interface-design.md §4.6). First-party tokens are unchanged.
  #
  # For a token bound to a resource:
  # - a `resource` sent with the code or refresh token must be the one
  #   granted (RFC 8707 §2.2), else invalid_target;
  # - a refresh token is revoked as soon as it is used (rotation, OAuth 2.1
  #   §4.3.1), and one unused for 30 days no longer works;
  # - presenting a refresh token that was already rotated away revokes every
  #   token of that authorization, since one copy must have been stolen;
  # - revocations are audited.
  class TokensController < Doorkeeper::TokensController
    def create
      error = check_public_api_request
      return render_token_error(*error) if error

      super
      rotate_refresh_token if response.successful?
    end

    def revoke
      target = revocable_token&.token
      was_live = target && !target.revoked?
      super
      return unless was_live && target.public_api? && target.reload.revoked?

      AuditEvent.record!("oauth.token_revoked", context: client_context, account: target.account, subject: target.application,
        metadata: { client_id: target.application&.uid, token_id: target.id, via: "rfc7009", token_type_hint: params[:token_type_hint].presence }.compact)
    end

    private

    # [error, description] or nil.
    def check_public_api_request
      case params[:grant_type]
      when "authorization_code"
        grant = Doorkeeper::AccessGrant.by_token(params[:code].to_s)
        return unless grant&.resource.present?

        resource_mismatch(grant.resource)
      when "refresh_token"
        @refreshed = Doorkeeper::AccessToken.by_refresh_token(params[:refresh_token].to_s)
        return unless @refreshed&.public_api?

        if @refreshed.revoked?
          detect_reuse(@refreshed)
          return [ "invalid_grant", "The refresh token has been used or revoked." ]
        end
        if @refreshed.refresh_idle_expired?
          @refreshed.revoke
          return [ "invalid_grant", "The refresh token expired after #{Settings::REFRESH_TOKEN_IDLE_LIFETIME.inspect} unused. Authorize again." ]
        end

        resource_mismatch(@refreshed.resource)
      end
    end

    def resource_mismatch(granted)
      return if params[:resource].blank?
      return if Settings.canonical_resource(params[:resource]) == granted

      [ "invalid_target", "The resource must be the one this authorization was granted for: #{granted}." ]
    end

    # A rotated-away refresh token has a successor (previous_refresh_token
    # points back at it). Seeing it again means two parties hold it.
    def detect_reuse(token)
      return unless Doorkeeper::AccessToken.exists?(previous_refresh_token: token.refresh_token)

      family = Doorkeeper::AccessToken.where(application_id: token.application_id, resource_owner_id: token.resource_owner_id,
        resource: token.resource, account_id: token.account_id, revoked_at: nil)
      revoked = family.update_all(revoked_at: Time.current)
      AuditEvent.record!("oauth.refresh_token_reused", context: client_context, account: token.account, subject: token.application,
        metadata: { client_id: token.application&.uid, token_id: token.id, tokens_revoked: revoked })
    end

    # Doorkeeper retires a used refresh token only when its successor's access
    # token is first used. Public-API refresh tokens are retired at once.
    def rotate_refresh_token
      @refreshed.revoke if @refreshed&.public_api? && !@refreshed.revoked?
    end

    def render_token_error(error, description)
      headers["Cache-Control"] = "no-store"
      render json: { error:, error_description: description }, status: :bad_request
    end

    def client_context = AuditEvent::Context.client(request)
  end
end
