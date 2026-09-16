class BaseAdminController < ApplicationController
  before_action :permit_admin!

  protected

  def permit_admin!
    permit! { current_user&.is_admin? }
  end
end
