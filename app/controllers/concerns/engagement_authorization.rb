module EngagementAuthorization
  extend ActiveSupport::Concern

  private

  # The User behind the presented OAuth token or API key.
  def engagement_user
    current_user
  end

  # Engaging requires a postal code (so we can attribute engagement
  # geographically). Users sign up via OAuth without one, so the frontend must
  # collect it (PATCH /api/v1/me) before the first endorse/critique succeeds.
  def require_postal_code!
    return if engagement_user&.engagement_ready?

    render json: { error: "postal_code_required" }, status: :unprocessable_entity
  end
end
