module Users
  # Devise OmniAuth callbacks. LinkedIn ("Sign In with LinkedIn using OpenID
  # Connect", via omniauth-linkedin-openid) establishes a Devise session so the
  # Doorkeeper authorize flow can issue an authorization code to TradingPost.
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def linkedin
      user = User.from_linkedin(request.env["omniauth.auth"])

      unless user.persisted?
        return redirect_to new_user_session_path,
          alert: user.errors.full_messages.to_sentence.presence || "Could not sign you in."
      end

      # Doorkeeper stashes the post-login target in session[:return_to]; a direct
      # "Continue with LinkedIn" click can pass one through omniauth.params.
      destination = session.delete(:return_to).presence ||
        safe_return_to(request.env.dig("omniauth.params", "return_to")) ||
        default_path(user)

      sign_in(:user, user)
      redirect_to destination, allow_other_host: false
    end

    def failure
      redirect_to new_user_session_path, alert: "LinkedIn sign-in failed. Please try again."
    end

    private

    def default_path(user)
      user.admin? ? admin_root_path : profile_path
    end

    # Only same-site, path-absolute redirects; rejects absolute and
    # protocol-relative ("//evil.com") values.
    def safe_return_to(input)
      input.to_s.match?(%r{\A/(?!/)}) ? input : nil
    end
  end
end
