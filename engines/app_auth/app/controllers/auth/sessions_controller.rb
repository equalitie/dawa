module Auth
  class SessionsController < ::ApplicationController
    include Auth::LoginAttempt

    protect_from_forgery with: :exception
    optional_authentication
    optional_authorization
    layout "inset"

    # we skip the CSRF check for logout so that javascript
    # service workers can log the user out. TODO...
    # skip_before_action :verify_authenticity_token, only: [:destroy]

    def new
      render :new
    end

    #
    # TURBO /auth/sessions/initiate
    #
    def initiate
      user = User.find_by_login!(params[:login])
      permit! { current_user.nil? || current_user == user }

      options = options_for_get_pubkey(
        user: user,
        credential: user.credentials.webauthn.find_by_webauthn_id(params[:webauthnId])
      )

      session[:timezone] = params[:timezone] if params[:timezone]
      session[:locale] = params[:locale] if params[:locale]
      session[:verify_user_id] = user.id
      session[:verify_challenge] = options["challenge"]

      render json: options
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    #
    # TURBO /auth/sessions/verify
    #
    def verify
      user = User.find(session[:verify_user_id])
      permit! { current_user.nil? || current_user == user }

      webauthn_credential = WebAuthn::Credential.from_get(params[:credential])
      credential_record = user.credentials.webauthn.where(authenticator_id: webauthn_credential.id).take
      webauthn_credential.verify(
        session[:verify_challenge],
        public_key: credential_record.public_key,
        sign_count: credential_record.sign_count.to_i,
        user_verification: true
      )
      credential_record.update!(
        sign_count: webauthn_credential.sign_count.to_s
      )

      if params[:setupOnly]
        unlock_vault(credential_record)
        location = nil
      else
        vault = unlock_vault(credential_record)
        cleanup_vaults(user, vault)
        set_current_user!(user, preserve: :redirect, vault: vault)
        if credential_record.encryption?
          login_attempt(:success, user, credential_record)
          location = url_from(session[:redirect]) || helpers.evaluate_route(Auth.home_url)
        else
          location = phrase_session_url
          session[:forced_location] = location
        end
      end
      render status: :ok, json: { status: "ok", location: location }
    rescue WebAuthn::Error => e
      login_attempt(:failure, user, credential_record)
      render json: { error: t("auth.verify_passkey_failed", error: e.message) }, status: :unprocessable_content
    rescue StandardError => e
      login_attempt(:failure, user, credential_record)
      render json: { error: e.message }, status: :unprocessable_content
    ensure
      session.delete(:verify_user_id)
      session.delete(:verify_challenge)
    end

    #
    # solicit or confirm a user's encryption phrase.
    # for use when webauthn prf is not supported.
    #
    def phrase
      if request.request_method == "POST"
        cred = current_user.credentials.phrase.take
        if vault = cred&.read_vault(params[:encryption_phrase])
          current_vault.set(vault)
          login_attempt(:success, current_user, cred)
          session.delete(:forced_location)
          redirect_to(url_from(session[:redirect]) || helpers.evaluate_route(Auth.home_url))
        else
          @error = t("auth.wrong_encryption_phrase")
          login_attempt(:failure, current_user, cred)
          render :phrase, status: :unprocessable_content
        end
      end
    end

    def destroy
      if current_user
        unless current_user.anon?
          Auth::Session.where(user_id: current_user.id).destroy_all
        end
        reset_session
        flash[:info] = t("auth.logged_out")
      end
      redirect_to helpers.evaluate_route(Auth.root_url)
    end

    protected

    #
    # options sent to browser for:
    #
    # navigator.credentials.get({ publicKey: options })
    #
    def options_for_get_pubkey(user:, credential: nil)
      if credential
        credentials = [ credential ]
      else
        credentials = user.credentials.webauthn.load
      end

      prf = { "evalByCredential" => {} }
      credentials.each do |cred|
        prf["evalByCredential"][cred.webauthn_id] = {
          "first" => Base64.urlsafe_encode64(cred.vault_seed)
        }
      end

      options = WebAuthn::Credential.options_for_get(
        allow: credentials.map { it.webauthn_id },

        # this forces the user to enter a pin or biometric confirmation
        # if supported by the authenticator. since we use passkeys as
        # a single factor, it seems good to require user verification
        user_verification: "required"
      )

      #
      # there appears to be a bug in Webauthn::Credential where
      # if we pass the extensions to options_for_get() it will
      # remove "_" from values in the hash. So, we add the extension
      # directly to the json.
      #
      JSON.parse(options.to_json).merge({
        "extensions" => { "prf" => prf }
      })
    end

    def unlock_vault(credential)
      prf_result = Base64.urlsafe_decode64(params["client_extension_results"]&.dig("prf", "results", "first")) rescue nil
      if prf_result
        if !credential.encryption?
          # if encryption keys are not yet created, initialize the vault
          credential.init_vault(prf_result)
          if current_user
            credential.update_vault(current_vault)
          end
        end
        credential.read_vault(prf_result)
      else
        nil
      end
    end

    #
    # remove keys the `user` should not have in `vault`.
    #
    # A user may have been removed from a workspace since the last time
    # they logged in. We need to check to confirm their membership in workspaces
    # in their vault, and remove the vault items that need to be removed.
    #
    def cleanup_vaults(user, vault)
      return unless vault
      update = false
      # FYI: vault is a hash of {"workspace/n" => "hex key material} so
      # vault.keys is the indexes to the vault, not the key material.
      vault.keys.each do |index|
        if index.start_with?("workspace/")
          id = index.sub(/^workspace\//, "").to_i
          unless user.ws_ids.include?(id)
            # double check in case ws_ids is wrong. it is catastrophic to delete
            # keys from a vault incorrectly.
            unless user.memberships.pluck(:workspace_id).include?(id)
              vault.delete(index)
              update = true
            end
          end
        end
      end
      if update
        user.credentials.update_vaults(vault)
      end
    end
  end
end
