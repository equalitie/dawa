class HomeController < ApplicationController

  before_action :permit_current_user!

  def show
    if !current_user.is_active?
      redirect_to step_enroll_path(step: "name")
    end
  end
end
