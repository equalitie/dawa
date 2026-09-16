class RootController < ApplicationController
  optional_authentication
  optional_authorization
  skip_before_action :permit_admin!

  layout "inset"

  def show
    if current_user&.is_active?
      redirect_to home_url
    end
    #theme.show_sidebar = false
  end
end
