module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[edit update destroy send_password_reset]
    before_action :prevent_self_management!, only: %i[edit update destroy send_password_reset]
    before_action :require_superadmin!, only: %i[destroy]

    def index
      scope = User.order(created_at: :desc)
      scope = scope.where("email ILIKE ? OR name ILIKE ?",
        "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%",
        "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%") if params[:q].present?
      @pagy, @users = pagy(scope)
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      @user.password = Devise.friendly_token(20)

      if @user.save
        @user.send_reset_password_instructions
        redirect_to admin_users_path, notice: "User created. Password reset email sent."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attrs = user_params.reject { |_, v| v.blank? }

      if @user.update(attrs)
        redirect_to admin_users_path, notice: "User updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def send_password_reset
      @user.send_reset_password_instructions
      redirect_to admin_users_path, notice: "Password reset email sent to #{@user.email}."
    end

    def destroy
      @user.destroy
      redirect_to admin_users_path, notice: "User deleted."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def prevent_self_management!
      if @user.id == current_user.id
        redirect_to admin_users_path, alert: "You cannot manage your own account here."
      end
    end

    def require_superadmin!
      redirect_to admin_users_path, alert: "Only superadmins can delete users." unless current_user.superadmin?
    end

    def user_params
      permitted = params.require(:user).permit(:name, :email, :role,
        :postal_code, :address_line1, :address_line2, :city, :province)

      if permitted[:role] == "superadmin" && !current_user.superadmin?
        permitted.delete(:role)
        flash[:alert] = "Only superadmins can assign the superadmin role."
      end

      permitted
    end
  end
end
