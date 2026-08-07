module Users
  class PasswordsController < ActionController::Base
    layout "login"

    # GET /password/new
    def new
    end

    # POST /password
    def create
      user = User.find_by(email: params.dig(:user, :email))

      if user
        user.send_reset_password_instructions
        # PostHog: track password reset request
        PostHog.capture(
          distinct_id: user.posthog_distinct_id,
          event: "password_reset_requested"
        )
      end

      redirect_to new_user_session_path, notice: "If that email exists, reset instructions have been sent."
    end

    # GET /password/edit?reset_password_token=...
    def edit
      @reset_password_token = params[:reset_password_token]
    end

    # PUT /password
    def update
      user = User.reset_password_by_token(
        reset_password_token: params.dig(:user, :reset_password_token),
        password: params.dig(:user, :password),
        password_confirmation: params.dig(:user, :password_confirmation)
      )

      if user.errors.empty?
        sign_in(:user, user)
        redirect_to profile_path, notice: "Password updated."
      else
        @reset_password_token = params.dig(:user, :reset_password_token)
        flash.now[:alert] = user.errors.full_messages.join(", ")
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
