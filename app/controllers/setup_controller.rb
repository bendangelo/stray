class SetupController < ApplicationController
  allow_unauthenticated_access
  before_action :redirect_if_users_exist

  def new
    @user = User.new
  end

  def create
    if User.any?
      redirect_to root_path and return
    end

    @user = User.new(setup_params)
    @user.admin = true
    if @user.save
      redirect_to new_session_path, notice: "Account created. Please sign in."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def redirect_if_users_exist
    redirect_to root_path if User.any?
  end

  def setup_params
    params.require(:user).permit(:username, :email, :password, :password_confirmation)
  end
end
