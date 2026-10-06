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

      # No internal id by default — most clients identify users by email. A
      # token granted the optional `identity` scope also receives the stable
      # York user id (as a string), for clients that must not key on email.
      def user_json(user)
        json = {
          email: user.email,
          name: user.name,
          role: user.role,
          avatar_url: user.avatar_url,
          postal_code: user.postal_code,
          engagement_ready: user.engagement_ready?,
          admin: user.admin?
        }
        json[:id] = user.id.to_s if identity_scope?
        json
      end

      # Both the token and its application must carry `identity`. Doorkeeper
      # lets an application registered with no scopes request any configured
      # scope, so the token's scope alone is not enough: only applications
      # explicitly registered with `identity` (the member app platform) see
      # the id.
      def identity_scope?
        token = doorkeeper_token
        return false if current_api_key || token.nil?

        token.includes_scope?("identity") &&
          Doorkeeper::OAuth::Scopes.from_string(token.application&.scopes.to_s).exists?("identity")
      end
    end
  end
end
