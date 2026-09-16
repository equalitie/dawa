class UsersController < ApplicationController
  before_action { permit_admin! }

  before_action :fetch_user, only: [ :show, :edit, :update, :destroy ]

  def index
    @users = User.order(:username)
  end

  def show
    @sessions = Auth::Session.where(user: @user).order(created_at: :desc).limit(20)
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to @user, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to @user, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy!
    redirect_to users_path, notice: t(".destroyed")
  end

  private

  def fetch_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:username, :email, :display_name, :is_active, :is_admin)
  end
end
