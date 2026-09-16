#
# Login as a demo user without any credentials
#
if !Conf.demo
  class Demo::SessionsController
  end
else
  class Demo::SessionsController < ApplicationController
    include Auth::LoginAttempt
    optional_authentication
    optional_authorization

    def create
      permit! { true }
      user = User.find_by_login(allowed_username(params[:username]))
      if user
        credential = user.credentials.where(type: "Auth::Credential::Demo").take
        set_current_user!(user, preserve: [:redirect])
        login_attempt(:success, user, credential)
        session[:timezone] ||= params[:timezone]
        session[:locale] ||= params[:locale]
        redirect_to session[:redirect] || root_url
      else
        raise Auth::UnauthenticatedRequest
      end
    end

    #
    # for writing tests
    #
    def update
      permit! { true }
      params.slice(*ALLOWED_SESSION_KEYS).each do |key, value|
        session[key] = value
      end
      render json: {}
    end

    private

    ALLOWED_SESSION_KEYS = [ :verify_user_id, :verify_challenge ]

    ALLOWED = [
      "demo", "demo-admin", "demo-user", "testy", "test1", "test2"
    ]

    # just to be extra cautious, only allow some usernames
    def allowed_username(username)
      if !Rails.env.test? && !ALLOWED.include?(username)
        raise ArgumentError, "username not allowed"
      end
      username
    end
  end
end
