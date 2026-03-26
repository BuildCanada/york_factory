module Admin
  class SessionsController < ActionController::Base
    layout "admin_login"

    def new
      redirect_to admin_root_path if session[:admin_user_id] && User.find_by(id: session[:admin_user_id])&.admin?
    end

    def create
      user = User.find_by(email: params[:email])
      if user&.valid_password?(params[:password]) && user.admin?
        session[:admin_user_id] = user.id
        redirect_to admin_root_path, notice: "Signed in."
      else
        flash.now[:alert] = "Invalid email or password."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      session.delete(:admin_user_id)
      redirect_to admin_login_path, notice: "Signed out."
    end
  end
end
