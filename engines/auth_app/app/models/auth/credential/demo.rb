#
# This is an authenticator that disregards
# any secret and just always self-authenticates
# with the stored secret.
#

module Auth
  class Credential::Demo < Auth::Credential
    attribute :authenticator, default: -> { SecureRandom.hex(32) }
    attribute :authenticator_id, default: -> { SecureRandom.hex(32) }

    def label
      "Demo Credential"
    end

    def comment
      "Automatic Encryption"
    end

    def deletable?
      false
    end

    def editable?
      false
    end

    def key_from_secret(secret)
      Auth.key_provider.key(
        secret: authenticator,
        salt: authenticator_id,
        bytes: RbNaCl::PrivateKey::BYTES
      )
    end
  end
end
