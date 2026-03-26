module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        def create
          google_token = params[:token]
          return render json: { error: "Token required" }, status: :bad_request unless google_token

          user_info = verify_google_token(google_token)
          return render json: { error: "Invalid token" }, status: :unauthorized unless user_info

          user = User.from_google(user_info)

          token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
          render json: {
            token: token,
            user: {
              id: user.id,
              email: user.email,
              name: user.name,
              admin: user.admin?,
              avatar_url: user.avatar_url
            }
          }
        end

        def destroy
          token = request.headers["Authorization"]&.split(" ")&.last
          return render json: { error: "No token" }, status: :bad_request unless token

          begin
            payload = JWT.decode(token, devise_jwt_secret, true, algorithm: "HS256").first
            JwtDenylist.create!(jti: payload["jti"], exp: Time.at(payload["exp"]))
            render json: { message: "Logged out" }, status: :ok
          rescue JWT::DecodeError
            render json: { error: "Invalid token" }, status: :unauthorized
          end
        end

        private

        def verify_google_token(token)
          uri = URI("https://oauth2.googleapis.com/tokeninfo?id_token=#{token}")
          response = Net::HTTP.get_response(uri)
          return nil unless response.is_a?(Net::HTTPSuccess)

          data = JSON.parse(response.body)
          return nil unless data["aud"] == ENV["GOOGLE_CLIENT_ID"]

          {
            provider: "google_oauth2",
            uid: data["sub"],
            email: data["email"],
            name: data["name"],
            avatar_url: data["picture"]
          }
        rescue StandardError
          nil
        end

        def devise_jwt_secret
          ENV.fetch("DEVISE_JWT_SECRET_KEY", Rails.application.secret_key_base)
        end
      end
    end
  end
end
