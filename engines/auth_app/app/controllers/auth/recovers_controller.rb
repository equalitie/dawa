module Auth
  class RecoversController < ::ApplicationController
    include Auth::LoginAttempt

    rate_limit to: 5, within: 5.minutes, only: :create

    optional_authentication
    optional_authorization
    layout "inset"

    def show
    end

    def create
      recovery_code = params[:recovery_code]
      credential = Auth::Credential::Recovery.find_by_code(params[:recovery_code])
      vault = credential&.read_vault(recovery_code)
      if vault.nil?
        login_attempt(:failure, credential&.user, credential)
        flash.now[:danger] = t("auth.invalid_recovery_code")
        render :show, status: :unprocessable_entity
      else
        set_current_user!(credential.user, vault: vault)
        login_attempt(:success, credential.user, credential)
        redirect_to main_app.home_url
      end
    end
  end
end
