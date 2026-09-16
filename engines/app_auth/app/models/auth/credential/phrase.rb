module Auth
  class Credential::Phrase < Auth::Credential
    alias_attribute :salt, :authenticator
    attribute :salt, default: -> { SecureRandom.hex(Auth.key_provider.pb_key_salt_bytes) }

    def label
      "Encryption Phrase"
    end

    #
    # phrases are automatically deleted when there are no keys that need them anymore
    #
    def deletable?
      false
    end

    def editable?
      true
    end

    def key_from_secret(user_supplied_secret)
      Auth.key_provider.pb_key(
        secret: secret,
        salt: self.salt
      )
    end
  end
end
