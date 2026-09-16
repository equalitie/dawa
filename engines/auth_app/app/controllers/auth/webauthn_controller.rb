module Auth
  class WebauthnController < ApplicationController
    optional_authentication
    optional_authorization

    #
    # step 1: create registration options and send to browser
    #
    def register_initiate
      if !current_user.webauthn_id
        current_user.update!(webauthn_id: WebAuthn.generate_user_id)
      end

      seed = Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)
      # https://developer.mozilla.org/en-US/docs/Web/API/PublicKeyCredentialCreationOptions
      options = WebAuthn::Credential.options_for_create(
        user: { id: current_user.webauthn_id, name: current_user.username },
        exclude: current_user.credentials.webauthn.map { |c| c.webauthn_id },
        attestation: "direct", # required to get AAGUID from authenticator
        timeout: 60_000, # 1 minute
        extensions: {
          prf: { eval: { first: seed } }
        }
      )
      session[:registration_seed] = seed
      session[:registration_challenge] = options.challenge

      render json: options
    end

    #
    # step 2: receive public key information from authenticator and verify
    # the registration challenge.
    #
    def register_verify
      webauthn_credential = WebAuthn::Credential.from_create(params[:credential])

      # we have to turn on "direct" attestation in order to get the aaguid from
      # some authenticators (e.g. ones that follow the spec like yubikey), but
      # we don't actually want to do attestation, I think, because some
      # authenticators won't pass attestation. The purpose of attestation is to
      # prove that the authenticator is really of the type that it claims to be.
      # It could catch fraudulent security keys but unfortunately the chances of
      # a false attestation failure are high.
      attestation_response = webauthn_credential.response
      def attestation_response.valid_attestation_statement?
        true
      end

      challenge = session.delete(:registration_challenge)
      webauthn_credential.verify(challenge, user_verification: true)
      seed        = Base64.urlsafe_decode64(session.delete(:registration_seed)) rescue nil
      aaguid      = webauthn_credential.response.authenticator_data.aaguid rescue nil
      prf_enabled = params["client_extension_results"]&.dig("prf", "enabled")

      credential_record = create_credential_record
      saved = credential_record.update(
        webauthn_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count.to_s,
        aaguid: aaguid,
        vault_seed: seed,
        prf_enabled: prf_enabled
      )

      if saved
        initialize_vault!(credential_record)
        render_success
      else
        render_error(t("auth.save_credential_failed"))
        Rails.logger.error(credential_record.errors.full_messages.join(' '))
      end
    rescue StandardError => e
      render_error(e.to_s)
    rescue WebAuthn::Error => e
      render_error(t("auth.verification_failed", error: e.message))
    end

    protected

    def initialize_vault!(credential)
      prf_result = Base64.urlsafe_decode64(params["client_extension_results"]&.dig("prf", "results", "first")) rescue nil
      if prf_result
        credential.init_vault(prf_result)
        unless credential.update_vault(current_vault.to_h)
          raise ArgumentError, "Could not save the credential's vault"
        end
      end
    end

    def render_success
      render json: { status: "ok" }, status: :ok
    end

    def render_error(msg)
      render json: { status: "error", error: msg }, status: :unprocessable_content
    end

    def create_credential_record
      if params["recordId"]
        current_user.credentials.find(params["recordId"])
      else
        current_user.credentials.create!(
          type: "Auth::Credential::Webauthn",
          is_active: false
        )
      end
    end
  end
end
