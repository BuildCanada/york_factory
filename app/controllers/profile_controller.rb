class ProfileController < ActionController::Base
  layout "profile"

  before_action :require_login!
  before_action :set_user

  def show
  end

  def update
    attrs = profile_params.reject { |_, v| v.blank? }

    if @user.update(attrs)
      # PostHog: re-identify with updated properties and capture profile update
      PostHog.identify(
        distinct_id: @user.posthog_distinct_id,
        properties: @user.posthog_properties
      )
      PostHog.capture(
        distinct_id: @user.posthog_distinct_id,
        event: "profile_updated",
        properties: {
          fields_updated: attrs.keys
        }
      )
      redirect_to profile_path, notice: "Profile updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def require_login!
    redirect_to new_user_session_path unless user_signed_in?
  end

  def set_user
    @user = current_user
  end

  def profile_params
    params.require(:user).permit(:name, :email,
      :postal_code, :address_line1, :address_line2, :city, :province)
  end
end
