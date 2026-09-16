#
# Webauthn IDs are Base64 url safe encoded. We keep them that
# way since that is how we receive and send them to javascript.
#

module Auth
  class Credential::Webauthn < Auth::Credential
    store_accessor :data, :sign_count, :aaguid, :prf_enabled
    alias_attribute :public_key, :authenticator
    alias_attribute :webauthn_id, :authenticator_id

    def label
      if aaguid
        Auth::AAGUID[aaguid]
      else
        "Passkey"
      end
    end

    def comment
      if encryption?
        "Automatic Encryption"
      else
        "Phrase Required"
      end
    end

    def supports_prf?
      prf_enabled
    end

    def editable?
      !encryption?
    end
  end
end
