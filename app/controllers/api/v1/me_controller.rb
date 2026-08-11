module Api
  module V1
    # Userinfo endpoint for OAuth clients. Returns the profile of the user who
    # owns the presented Doorkeeper access token, including their admin status so
    # clients can gate admin-only UI (e.g. TradingPost draft preview).
    class MeController < ApplicationController
      before_action :authenticate_api_user!

      def show
        user = current_token_user
        return render(json: { error: "Unauthorized" }, status: :unauthorized) unless user

        render json: user_json(user)
      end

      # Lets OAuth clients complete the signed-in user's profile — currently just
      # the postal code required to endorse/critique a memo.
      def update
        user = current_token_user
        return render(json: { error: "Unauthorized" }, status: :unauthorized) unless user

        if user.update(me_params)
          render json: user_json(user)
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def current_token_user
        current_user
      end

      def me_params
        params.require(:user).permit(:postal_code, :name)
      end

      # Deliberately no internal id — clients identify users by email.
      def user_json(user)
        {
          email: user.email,
          name: user.name,
          role: user.role,
          avatar_url: user.avatar_url,
          postal_code: user.postal_code,
          engagement_ready: user.engagement_ready?,
          admin: user.admin?
        }
      end
    end
  end
end
