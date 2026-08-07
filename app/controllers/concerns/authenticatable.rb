module Authenticatable
  extend ActiveSupport::Concern

  private

  # Authenticates as the user who owns either a user API key or a live
  # Doorkeeper access token. API keys deliberately have no copied role/scope:
  # authorization always consults their owner, so permission changes take
  # effect immediately.
  def authenticate_api_user!
    if (api_key = current_api_key)
      @current_user = api_key.user
      return
    end

    doorkeeper_authorize!
    return if performed?

    @current_user = User.find_by(id: doorkeeper_token&.resource_owner_id)
    render_unauthorized unless @current_user
  end

  def authenticate_admin!
    if (api_key = current_api_key)
      @current_user = api_key.user
      return render_forbidden unless @current_user.admin?

      return
    end

    if doorkeeper_token&.accessible?
      @current_user = User.find_by(id: doorkeeper_token.resource_owner_id)
      return render_forbidden unless @current_user&.admin?

      return
    end

    token = bearer_token
    return render_unauthorized unless token

    begin
      payload = JWT.decode(token, devise_jwt_secret, true, algorithm: "HS256").first
      return render_unauthorized if JwtDenylist.exists?(jti: payload["jti"])
      @current_user = User.find(payload["sub"])
      return render_forbidden unless @current_user.admin? # rubocop:disable Style/RedundantReturn -- return halts before_action chain
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render_unauthorized
    end
  end

  def current_user
    @current_user
  end

  def current_api_key
    return @current_api_key if defined?(@current_api_key)

    @current_api_key = ApiKey.authenticate(bearer_token)
  end

  def bearer_token
    scheme, token = request.headers["Authorization"]&.split(" ", 2)
    token if scheme&.casecmp?("Bearer")
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
