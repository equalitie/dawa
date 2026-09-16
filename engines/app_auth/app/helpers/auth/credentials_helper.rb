module Auth
  module CredentialsHelper

    #
    # this button prompts the user to add a new passkey
    #
    def add_passkey_button(credential, controller)
      v.button(
        label: "Add Passkey", icon: "key",
        size: "lg", class: "btn-white",
        hide: credential&.registered?,
        data: controller.data(
          target: :hide_on_success,
          action: "click->webauthn#initiateRegistration",
          params: { record_id: credential&.id }
        )
      )
    end

    #
    # this is a dummy button that is shown after
    # a passkey has been added.
    #
    def passkey_added_button(credential, controller)
      v.button(
        label: "Passkey Added", icon: "check-lg",
        size: "lg", color: "success", fill: true,
        hide: !credential&.registered?,
        data: controller.target(:show_on_success)
      )
    end

    #
    # this button triggers a login action, but in "setupOnly" mode
    # where it initializes the credential's vault but doesn't actually
    # login
    #
    def enable_encryption_button(credential, controller)
      v.button(
        label: "Enable Encryption", icon: "key",
        size: "lg", class: "btn-white",
        hide: credential.encryption?,
        data: controller.data(
          target: "hide_on_success",
          action: "click->session#login",
          params: {
            setupOnly: true,                    # Don't login, just set up the credential's vault
            webauthnId: credential.webauthn_id  # limit acceptable passkeys to this one
          }
        )
      )
    end

    #
    # this is a dummy button that gets shown after enable_encryption_button
    # has been successfully pressed.
    #
    def encryption_enabled_button(credential, controller)
      v.button(
        label: "Encryption Enabled", icon: "check-lg",
        size: "lg", color: "success", fill: true,
        hide: !credential.encryption?,
        data: controller.target(:show_on_success)
      )
    end

    def attempt_user_agent(attempt)
      if attempt&.data&.present?
        [
          attempt.data["browser"],
          attempt.data["version"],
          "on",
          attempt.data["platform"]
        ].join(" ")
      end
    end
  end
end
