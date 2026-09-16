class RootController < ApplicationController
  optional_authentication
  optional_authorization

  layout "inset"

  def show
    if current_user
      if current_user.is_admin?
        redirect_to dashboard_url
      else
        redirect_to home_url
      end
    end
    #theme.show_sidebar = false
  end
end
