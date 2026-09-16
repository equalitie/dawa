class BaseUserController < ApplicationController
  before_action :permit_current_user!
  before_action :ensure_active

  protected

  def ensure_active
    if current_user
      if !current_user.is_active?
        error_message!("Account is not active")
      elsif !current_user.is_finalized?
        redirect_to step_enroll_path(step: "name")
      end
    end
  end
end
