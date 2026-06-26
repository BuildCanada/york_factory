module Users
  # Browser OIDC sign-in with LinkedIn. Establishes a Devise session (cookie) so
  # the Doorkeeper authorize endpoint's resource_owner_authenticator sees a
  # current_user and can issue an authorization code to TradingPost.
  #
  # This mirrors the redirect dance a Devise omniauth provider would run, but
  # reuses the LinkedinOidc service (server-side code exchange + JWKS id_token
  # verification) rather than adding an omniauth strategy gem.
  class LinkedinController < ActionController::Base
    # The callback is a GET initiated by LinkedIn's redirect; CSRF is enforced
    # via the signed `state` round-trip below instead of a Rails token.
    protect_from_forgery with: :null_session

    def start
      session[:linkedin_state] = SecureRandom.hex(16)
      session[:linkedin_nonce] = SecureRandom.hex(16)
      # Preserve a return target only if Doorkeeper (or a caller) hasn't already
      # stashed one for after sign-in.
      if session[:return_to].blank? && params[:return_to].present?
        session[:return_to] = safe_return_to(params[:return_to])
      end

      redirect_to LinkedinOidc.authorize_url(state: session[:linkedin_state], nonce: session[:linkedin_nonce]),
        allow_other_host: true
    rescue LinkedinOidc::ConfigError => e
      fail_auth("LinkedIn sign-in is not configured: #{e.message}")
    end

    def callback
      return fail_auth("LinkedIn sign-in was cancelled.") if params[:error].present?
      return fail_auth("Sign-in expired or was tampered with. Please try again.") unless valid_state?

      tokens   = LinkedinOidc.exchange_code(params[:code])
      identity = LinkedinOidc.verify_id_token(tokens["id_token"], nonce: session[:linkedin_nonce])
      user     = User.from_linkedin(identity)

      unless user.persisted?
        return fail_auth(user.errors.full_messages.to_sentence.presence || "Could not sign you in.")
      end

      # Capture the post-login destination before reset_session clears it, then
      # rotate the session id (fixation guard) and sign in.
      destination = session.delete(:return_to).presence || default_path(user)
      reset_session
      sign_in(:user, user)
      redirect_to destination, allow_other_host: false
    rescue LinkedinOidc::Error, JWT::DecodeError, KeyError => e
      fail_auth(e.message)
    ensure
      session.delete(:linkedin_state)
      session.delete(:linkedin_nonce)
    end

    private

    def valid_state?
      expected = session[:linkedin_state].to_s
      given    = params[:state].to_s
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)
    end

    def default_path(user)
      user.admin? ? admin_root_path : profile_path
    end

    # Only same-site, path-absolute redirects; rejects absolute and
    # protocol-relative ("//evil.com") values.
    def safe_return_to(input)
      input.to_s.match?(%r{\A/(?!/)}) ? input : nil
    end

    def fail_auth(message)
      redirect_to new_user_session_path, alert: message
    end
  end
end
