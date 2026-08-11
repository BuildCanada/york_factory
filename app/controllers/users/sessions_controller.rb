module Users
  class SessionsController < ActionController::Base
    layout "login"

    def new
      redirect_to after_sign_in_path if user_signed_in?
    end

    def create
      user = User.find_by(email: params.dig(:user, :email) || params[:email])

      if user&.valid_password?(params.dig(:user, :password) || params[:password])
        reset_session
        sign_in(:user, user)

        # PostHog: identify user and capture login event
        PostHog.identify(
          distinct_id: user.posthog_distinct_id,
          properties: user.posthog_properties
        )
        PostHog.capture(
          distinct_id: user.posthog_distinct_id,
          event: "user_signed_in",
          properties: { login_method: "email" }
        )

        redirect_to after_sign_in_path, notice: "Signed in."
      else
        flash.now[:alert] = "Invalid email or password."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      sign_out(:user)
      redirect_to new_user_session_path, notice: "Signed out."
    end

    private

    def after_sign_in_path
      session.delete(:return_to).presence || (current_user.admin? ? admin_root_path : profile_path)
    end
  end
end
