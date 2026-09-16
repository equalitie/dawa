module Auth
  class CredentialsController < ApplicationController
    require_authentication
    before_action :permit_current_user!
    before_action :fetch_credential, only: [:edit, :update, :destroy]

    def index
      @credentials = current_user.credentials.visible.active
      @attempts    = paginate(current_user.attempts.order(created_at: :desc))
      @sessions    = Auth::Session.where(user: current_user)
      @webauthn_cred_count = current_user.credentials.webauthn.count

      respond_to do |format|
        format.turbo_stream
        format.html
      end
    end

    #
    # when a credential needs to be bound to a passkey
    # and/or set up encryption
    #
    def edit
      @credential = Auth::CredentialForm.new(@credential)
      render action: "edit", layout: "inset"
    end

    def update
      @credential = Auth::CredentialForm.new(@credential)
      if @credential.update(credential_params, current_vault)
        if @credential.is_active?
          redirect_to credentials_url
        else
          redirect_to edit_credential_url(@credential)
        end
      else
        render action: "edit", layout: "inset", status: :unprocessable_entity
      end
    end

    #
    # triggered when a user clicks "Add Passkey" or "Add Recovery Code"
    #
    def create
      type = if params[:type] == "webauthn"
        "Auth::Credential::Webauthn"
      elsif params[:type] == "recovery"
        "Auth::Credential::Recovery"
      end
      credential = current_user.credentials.create!(
        type: type,
        is_active: false
      )
      redirect_to edit_credential_path(credential)
    end

    def destroy
      if !@credential.encryption? && current_user.credentials.without_encryption.count == 1
        # if this is the last credential that requires a phrase credential,
        # then destroy the phrase credential
        current_user.credentials.phrase.destroy_all
      end
      @credential.destroy
      respond_to do |format|
        format.html {
          redirect_to credentials_path
        }
        format.turbo_stream {
          render turbo_stream: turbo_stream.remove(@credential)
        }
      end
    end

    private

    def fetch_credential
      @credential = current_user.credentials.find(params[:id])
    end

    def credential_params
      params.permit(credential: [ :name, :encryption_phrase ]).dig(:credential) || {}
    end
  end
end
