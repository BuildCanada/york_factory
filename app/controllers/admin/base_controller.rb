module Admin
  class BaseController < ActionController::Base
    layout "admin"
    include Pagy::Backend

    before_action :require_admin!

    private

    def require_admin!
      @current_admin = User.find_by(id: session[:admin_user_id])
      redirect_to admin_login_path unless @current_admin&.admin?
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
