module Authenticatable
  extend ActiveSupport::Concern

  private

  def authenticate_admin!
    token = request.headers["Authorization"]&.split(" ")&.last
    return render_unauthorized unless token

    begin
      payload = JWT.decode(token, devise_jwt_secret, true, algorithm: "HS256").first
      return render_unauthorized if JwtDenylist.exists?(jti: payload["jti"])
      @current_user = User.find(payload["sub"])
      render_forbidden unless @current_user.admin?
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render_unauthorized
    end
  end

  def current_user
    @current_user
  end

  def devise_jwt_secret
    ENV.fetch("DEVISE_JWT_SECRET_KEY", Rails.application.secret_key_base)
  end

  def render_unauthorized
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def render_forbidden
    render json: { error: "Forbidden" }, status: :forbidden
  end
end
