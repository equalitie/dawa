class TestSessionsController < ApplicationController
  include Auth::LoginAttempt
  optional_authentication
  optional_authorization

  def create
    user = User.find_by_login(params[:username])
    if user
      credential = user.credentials.where(type: "Auth::Credential::Demo").take
      set_current_user!(user, vault: credential&.read_vault("ignored"))
      login_attempt(:success, user, credential)
      session[:timezone] ||= params[:timezone]
      session[:locale] ||= params[:locale]
      redirect_to home_url
    else
      raise Auth::UnauthenticatedRequest
    end
  end

  def update
    params.each do |key, value|
      session[key] = value
    end
    render json: {}
  end

end
