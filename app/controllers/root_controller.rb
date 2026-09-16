class RootController < ApplicationController
  optional_authentication
  optional_authorization

  layout "inset"

  def show
    if current_user&.is_active?
      redirect_to home_url
    end
    #theme.show_sidebar = false
  end
end
