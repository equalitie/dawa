class EnrollController < ApplicationController
  optional_authentication
  optional_authorization
  helper "auth/credentials"

  skip_before_action :ensure_active
  before_action :fetch_records, only: [ :update, :show, :destroy ]
  before_action { @title = "Enroll" }
  before_action :allow_inactive_user

  layout "inset"

  # POST /enroll/start
  def start
    session[:timezone] ||= params[:timezone]
    redirect_to step_enroll_path(step: "name")
  end

  # GET /enroll/:step
  def show
    @user = UserForm.new(user: current_user)
  end

  # POST /enroll
  def create
    @user = UserForm.new(user_params).create
    if @user.persisted?
      set_current_user!(@user.user, preserve: :redirect)
      redirect_to next_step
    else
      render :show, status: :unprocessable_entity
    end
  end

  # PUT /enroll
  def update
    if params[:step] == "name" || params[:step] == "avatar"
      update_user
    elsif params[:step] == "credential"
      update_credential
    else
      redirect_to next_step
    end
  end

  def destroy
    if @user && !@user.is_active?
      @user.destroy
      reset_session
    end
    redirect_to root_url
  end

  protected

  def update_user
    @user = UserForm.new(user_params.merge(user: current_user)).update
    if @user.errors.empty?
      redirect_to next_step
    else
      render :show, status: :unprocessable_entity
    end
  end

  def update_credential
    @credential = Auth::CredentialForm.new(@credential)
    if @credential.update(credential_params)
      UserForm.new(user: @user).finalize_enrollment!
      set_current_user!(@user, preserve: :redirect)
      redirect_to(url_from(session[:redirect]) || home_url)
    else
      render :show, layout: "inset", status: :unprocessable_entity
    end
  end

  def user_params
    params.permit(user: [ :username, :display_name, :hue, :avatar_img, avatar: {} ]).dig(:user) || {}
  end

  def credential_params
    params.permit(credential: [ :name, :encryption_phrase ]).dig(:credential) || {}
  end

  def allow_inactive_user
    if @user&.is_active?
      redirect_to home_url
    end
  end

  def fetch_records
    @user = current_user
    if @user
      @credential = @user.credentials.webauthn.take
    end
  end

  def next_step
    if params[:step] == "name"
      step_enroll_path(step: "credential") # skip avatar for now
    elsif params[:step] == "avatar"
      step_enroll_path(step: "credential")
    else
      home_path
    end
  end
end
