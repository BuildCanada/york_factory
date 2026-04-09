module Admin
  class BaseController < ActionController::Base
    layout "admin"
    include Pagy::Method

    before_action :require_admin!

    private

    def require_admin!
      unless user_signed_in?
        redirect_to new_user_session_path and return
      end

      redirect_to new_user_session_path, alert: "Not authorized." unless current_user.admin?
    end

    def pagy_metadata(pagy)
      {
        page: pagy.page,
        pages: pagy.pages,
        count: pagy.count,
        per_page: pagy.limit
      }
    end
  end
end
