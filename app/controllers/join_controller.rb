class JoinController < ApplicationController
  optional_authentication
  optional_authorization

  layout "inset"

  def show
    @invite = Invite.find_by_code(params[:id])
    if @invite.nil?
      error_message! t("invites.error.not_found")
    elsif @invite.used?
      error_message! t("invites.error.used")
    elsif @invite.expired?
      error_message! t("invites.error.expired")
    end
  end

  def update
    @invite = Invite.find_by_code(params[:id])
    if @invite.nil? || @invite.expired? || @invite.used?
      raise_error
    else
      reset_and_preserve_session
      session[:current_invite] = @invite.id
      redirect_to step_enroll_path(step: "name")
    end
  end

  protected

  def raise_error
    head :bad_request
  end
end
