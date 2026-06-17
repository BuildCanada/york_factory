module Api
  module V1
    # Userinfo endpoint for OAuth clients. Returns the profile of the user who
    # owns the presented Doorkeeper access token, including their admin status so
    # clients can gate admin-only UI (e.g. TradingPost draft preview).
    class MeController < ApplicationController
      before_action :doorkeeper_authorize!

      def show
        user = User.find_by(id: doorkeeper_token.resource_owner_id)
        return render(json: { error: "Unauthorized" }, status: :unauthorized) unless user

        render json: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role,
          avatar_url: user.avatar_url,
          admin: user.admin?
        }
      end
    end
  end
end
