module Admin
  class UsersController < BaseController
    def index
      @users = User.order(created_at: :desc)
    end

    def edit
      @user = User.find(params[:id])
    end

    def update
      @user = User.find(params[:id])
      permitted = user_params

      permitted.delete(:password) if permitted[:password].blank?
      permitted.delete(:password_confirmation) if permitted[:password_confirmation].blank?

      admin_value = params.dig(:user, :admin)
      permitted[:admin] = ActiveModel::Type::Boolean.new.cast(admin_value) unless admin_value.nil?

      if @user.update(permitted)
        redirect_to admin_users_path, notice: "User updated"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @user = User.find(params[:id])
      if @user == current_user
        redirect_to admin_users_path, alert: "You cannot delete your own account"
      else
        @user.destroy!
        redirect_to admin_users_path, notice: "User deleted"
      end
    end

    private

    def user_params
      params.require(:user).permit(:username, :email, :password, :password_confirmation)
    end
  end
end
